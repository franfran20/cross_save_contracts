// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@axelar/contracts/interfaces/IAxelarExecutable.sol";
import "@axelar/contracts/interfaces/IAxelarGasService.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface IDIAOracleV2 {
    function getValue(string memory) external view returns (uint128, uint128);
}

contract CrossSave is IAxelarExecutable {
    ///@notice the moonbase chain name (string format)
    string public moonbaseChain = "Moonbeam";
    ///@notice the fantom chain id (string format)
    string public fantomChain = "Fantom";
    ///@notice cross save contract address deployed on moonbase (string format)
    string public moonbaseContractAddress;
    ///@notice cross save contract address deployed on fantom (string format)
    string public fantomContractAddress;
    ///@notice the key for the dia oracle
    string public KEY = "GLMR/USD";

    ///@notice the oracle address for glmr used by dia
    address public ORACLE;

    ///@notice the fantom chainid (uint256 format)
    uint256 public uintFantomChainId = 4002;
    ///@notice the moonbase chainid (uint256 format)
    uint256 public uintMoonbaseChainId = 1287;
    ///@notice the total time saved accross all chains
    uint256 public totalTimeSaved;
    ///@notice the total savers accross all chains
    uint256 public totalSavers;
    ///@notice the path followed for cross chain communication when a user saves
    uint256 public constant savingPath = 1;
    ///@notice the path followed for cross chain communication when a user unlocks their savings
    uint256 public constant unlockPath = 2;
    ///@notice the path followed for cross chain communication for a two way call for unlcoking savings
    uint256 public constant innerUnlockPath = 3;
    ///@notice the path followed for cross chain communication when a user defaults on savings
    uint256 public constant defaultPath = 4;
    ///@notice the percentage cut taken by cross save for users who break their savings too early
    uint256 public crossSaveCut = 50;
    ///@notice minimum saving time
    uint256 public minimumSavingTime;
    ///@notice minimum saving amount
    uint256 public minimumSavingAmount;

    ///@notice the deployers address
    address public deployer;

    ///@notice axelar gas receiver interface
    IAxelarGasService public gasReceiver;

    ///@notice chainlinks price feed interface
    AggregatorV3Interface internal priceFeed;

    ///@notice the total default balance to be shared by complete savers
    struct DefaultPoolBalance {
        int256 glmr; //moonbase
        int256 ftm; //fantom
    }

    ///@notice the default pool balance
    DefaultPoolBalance public defaultPoolBalance;

    ///@notice the user savings details
    struct UserSavings {
        uint256 amount; //balance
        uint256 startTime; // saving start time
        uint256 stopTime; //saving stop time
        uint256 status; //locked = 0 /unlocked = 1
        uint256 interest; // interest earned after complete savings
        string goal; //goal for saving e.g to get a toaster
    }

    ///@notice the user address to their savings detail
    mapping(address => UserSavings) public _savings;

    ///@notice keeps track of if a user already has a saving going on
    mapping(address => bool) public _isSaving;

    constructor(
        address _gateway,
        address _gasReceiver,
        address _priceFeed,
        uint256 _minimumSavingTime,
        uint256 _minimumSavingAmount
    ) IAxelarExecutable(_gateway) {
        gasReceiver = IAxelarGasService(_gasReceiver);
        priceFeed = AggregatorV3Interface(_priceFeed);
        minimumSavingTime = _minimumSavingTime;
        minimumSavingAmount = _minimumSavingAmount;
        ORACLE = _priceFeed;
        deployer = msg.sender;
    }

    ///@notice allows a user save a specified amount for a period of time
    ///@dev updates the users savings detail and updates all cross chain variables
    ///@param _savingTime the amount of time in seconds the user wishes to save for
    ///@param _sdkEstimatedGasCostFromMoonbase the gas cost for making cross chain calls from moonbase paid by the contract
    ///@param _sdkEstimatedGasCostFromFantom the gas cost for making cross chain calls from fantom paid by the contract
    ///@param _goal the reason for the saving
    function save(
        uint256 _savingTime,
        uint256 _sdkEstimatedGasCostFromMoonbase,
        uint256 _sdkEstimatedGasCostFromFantom,
        string memory _goal
    ) public payable {
        require(_savings[msg.sender].status == 0, "Status !locked");
        require(_savingTime > minimumSavingTime, "Time too low");
        require(msg.value > minimumSavingAmount, "Amount too low");

        _savings[msg.sender].amount += msg.value;

        if (!_isSaving[msg.sender]) {
            _savings[msg.sender].startTime = block.timestamp;
            _savings[msg.sender].stopTime = block.timestamp + _savingTime;
            _isSaving[msg.sender] = true;
            _savings[msg.sender].goal = _goal;
        } else {
            _savings[msg.sender].stopTime = _savings[msg.sender]
                .stopTime += _savingTime;
        }

        if (block.chainid == uintMoonbaseChainId) {
            bytes memory payload = abi.encode(
                savingPath,
                _savingTime,
                msg.value,
                0,
                address(0)
            );
            _callFantomChain(payload, _sdkEstimatedGasCostFromMoonbase);
        }

        if (block.chainid == uintFantomChainId) {
            bytes memory payload = abi.encode(
                savingPath,
                _savingTime,
                msg.value,
                0,
                address(0)
            );
            _callMoonbaseChain(payload, _sdkEstimatedGasCostFromFantom);
        }

        totalSavers++;
        totalTimeSaved += _savingTime;
    }

    ///@notice allows the user to unlock their savings after a complete saving duration
    ///@dev makes cross chain calculation of the total default pool of all assets across chain for the users interest
    ///@param _sdkEstimatedGasCostFromMoonbase the gas cost for making cross chain calls from moonbase paid by the contract
    ///@param _sdkEstimatedGasCostFromFantom the gas cost for making cross chain calls from fantom paid by the contract
    function unlockSavings(
        uint256 _sdkEstimatedGasCostFromMoonbase,
        uint256 _sdkEstimatedGasCostFromFantom
    ) public {
        require(_isSaving[msg.sender], "You have no savings");
        require(
            block.timestamp > _savings[msg.sender].stopTime,
            "Break Save Instead"
        );

        uint256 userSavingTime = _savings[msg.sender].stopTime -
            _savings[msg.sender].startTime;

        if (block.chainid == uintMoonbaseChainId) {
            uint256 glmrUsdPrice = getGlmrPriceInUsd();

            uint256 glmrDefaultPoolAmountInUsd;
            if (defaultPoolBalance.glmr > 0) {
                glmrDefaultPoolAmountInUsd =
                    (uint256(defaultPoolBalance.glmr) * getGlmrPriceInUsd()) /
                    10 ** 18;
            } else {
                glmrDefaultPoolAmountInUsd = 0;
            }

            bytes memory payload = abi.encode(
                unlockPath,
                glmrUsdPrice,
                glmrDefaultPoolAmountInUsd,
                userSavingTime,
                msg.sender
            );
            _callFantomChain(payload, _sdkEstimatedGasCostFromMoonbase);
        }

        if (block.chainid == uintFantomChainId) {
            uint256 ftmUsdPrice = getFtmPriceInUsd();

            uint256 ftmDefaultPoolAmountInUsd;
            if (defaultPoolBalance.ftm > 0) {
                ftmDefaultPoolAmountInUsd =
                    (uint256(defaultPoolBalance.ftm) * getFtmPriceInUsd()) /
                    10 ** 18;
            } else {
                ftmDefaultPoolAmountInUsd = 0;
            }

            bytes memory payload = abi.encode(
                unlockPath,
                ftmUsdPrice,
                ftmDefaultPoolAmountInUsd,
                userSavingTime,
                msg.sender
            );
            _callMoonbaseChain(payload, _sdkEstimatedGasCostFromFantom);
        }

        totalTimeSaved -= userSavingTime;
        totalSavers -= 1;

        _savings[msg.sender].startTime = 0;
        _savings[msg.sender].stopTime = 0;
        _isSaving[msg.sender] = false;
    }

    ///@notice allows the user to withdraw their savings after unlock with either the interest or slashed value
    ///@dev resets some of the user savings details
    function withdrawSavings() public {
        require(_savings[msg.sender].status == 1, "!unlcoked");

        uint256 balance = _savings[msg.sender].amount +
            _savings[msg.sender].interest;

        _savings[msg.sender].interest = 0;
        _savings[msg.sender].amount = 0;

        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "!successful");

        _savings[msg.sender].status = 0;
        _savings[msg.sender].goal = "";
    }

    ///@notice allows a user to default on their save due to personal reasons
    ///@dev allows a user to break a save but lose a percentage of the save set by crosssave
    function defaultOnSave(
        uint256 _sdkEstimatedGasCostFromMoonbase,
        uint256 _sdkEstimatedGasCostFromFantom
    ) public {
        require(
            block.timestamp < _savings[msg.sender].stopTime,
            "Unlock Instead"
        );

        uint256 userAmountAfterCut = (_savings[msg.sender].amount *
            crossSaveCut) / 100;
        uint256 userSavingTime = _savings[msg.sender].stopTime -
            _savings[msg.sender].startTime;

        if (block.chainid == uintMoonbaseChainId) {
            bytes memory payload = abi.encode(
                defaultPath,
                userSavingTime,
                userAmountAfterCut,
                0,
                address(0)
            );

            _callFantomChain(payload, _sdkEstimatedGasCostFromMoonbase);
            defaultPoolBalance.glmr += int256(userAmountAfterCut);
        }

        if (block.chainid == uintFantomChainId) {
            bytes memory payload = abi.encode(
                defaultPath,
                userSavingTime,
                userAmountAfterCut,
                0,
                address(0)
            );

            _callMoonbaseChain(payload, _sdkEstimatedGasCostFromFantom);
            defaultPoolBalance.ftm += int256(userAmountAfterCut);
        }

        totalTimeSaved -= userSavingTime;
        totalSavers -= 1;
        _isSaving[msg.sender] = false;

        _savings[msg.sender].amount = userAmountAfterCut;
        _savings[msg.sender].status = 1; //unlocked
        _savings[msg.sender].stopTime = 0;
        _savings[msg.sender].startTime = 0;
    }

    function updateStringContractAddresses(
        string memory _moonbaseContractAddress,
        string memory _fantomContractAddress
    ) public {
        require(msg.sender == deployer, "!deployer");
        moonbaseContractAddress = _moonbaseContractAddress;
        fantomContractAddress = _fantomContractAddress;
    }

    // INTERNAL FUNCTIONS

    ///@notice the function that handles the cross chain calling from the fantom chain to moonbase chain
    ///@dev the contracts pays for the cross chain messaging gas and sends the encoded payload
    ///@param payload the encoded parameters dependent on the path
    ///@param _estimatedGas the gas the crosssave contracts pays for making the call calculated from the client via axelars sdk
    function _callMoonbaseChain(
        bytes memory payload,
        uint256 _estimatedGas
    ) public {
        gasReceiver.payNativeGasForContractCall{value: _estimatedGas}(
            address(this),
            moonbaseChain,
            moonbaseContractAddress,
            payload,
            address(this)
        );

        gateway.callContract(moonbaseChain, moonbaseContractAddress, payload);
    }

    ///@notice the function that handles the cross chain calling from the moonbase chain to fantom chain
    ///@dev the contracts pays for the cross chain messaging gas and sends the encoded payload
    ///@param payload the encoded parameters dependent on the path
    ///@param _estimatedGas the gas the crosssave contracts pays for making the call calculated from the client via axelars sdk
    function _callFantomChain(
        bytes memory payload,
        uint256 _estimatedGas
    ) public {
        gasReceiver.payNativeGasForContractCall{value: _estimatedGas}(
            address(this),
            fantomChain,
            fantomContractAddress,
            payload,
            address(this)
        );

        gateway.callContract(fantomChain, fantomContractAddress, payload);
    }

    ///@notice the entry point function called by the axelar gateway to pass in the encoded parameters from teh source chain to this chain(destination chain)
    ///@param payload the encoded parameters dependent on the path
    function _execute(
        string memory,
        string memory,
        bytes calldata payload
    ) internal override {
        (
            uint256 path,
            uint256 var1,
            uint256 var2,
            uint256 var3,
            address var4
        ) = abi.decode(payload, (uint256, uint256, uint256, uint256, address));

        // var 1 - the users saving time from source chain
        // var 2 - the amount of source chain asset saved
        // var 3 - unused paramte
        if (path == savingPath) {
            totalSavers++;
            totalTimeSaved += var1;
        }

        // var 1 - source chain asset price in usd
        // var 2 - source chain asset default pool amount in usd
        // var 3 - source chain user saving time
        if (path == unlockPath) {
            if (block.chainid == uintMoonbaseChainId) {
                uint256 glmrDefaultPoolAmountInUsd;

                if (defaultPoolBalance.glmr <= 0) {
                    glmrDefaultPoolAmountInUsd = 0;
                } else {
                    glmrDefaultPoolAmountInUsd =
                        (uint256(defaultPoolBalance.glmr) *
                            getGlmrPriceInUsd()) /
                        10 ** 18;
                }

                uint256 totalDefaultPoolBalanceInUsd = var2 +
                    glmrDefaultPoolAmountInUsd;

                uint256 interestInUsdForSaver;
                if (totalDefaultPoolBalanceInUsd <= 0) {
                    interestInUsdForSaver = 0;
                } else {
                    interestInUsdForSaver =
                        (var3 * totalDefaultPoolBalanceInUsd) /
                        totalTimeSaved;
                }

                uint256 interestInNativeAssetOfSourceChain;
                if (interestInUsdForSaver <= 0) {
                    interestInNativeAssetOfSourceChain = 0;
                } else {
                    interestInNativeAssetOfSourceChain =
                        (10 ** 18 * interestInUsdForSaver) /
                        var1;
                }

                // locked = 0 / unlocked = 1
                // uint256 unlocked = 1;

                totalTimeSaved -= var3;
                totalSavers -= 1;
                defaultPoolBalance.ftm -= int256(
                    interestInNativeAssetOfSourceChain
                );

                bytes memory innerPayload = abi.encode(
                    innerUnlockPath,
                    1,
                    interestInNativeAssetOfSourceChain,
                    0,
                    var4
                );

                gateway.callContract(
                    fantomChain,
                    fantomContractAddress,
                    innerPayload
                );
            }

            if (block.chainid == uintFantomChainId) {
                uint256 ftmDefaultPoolAmountInUsd;

                if (defaultPoolBalance.ftm <= 0) {
                    ftmDefaultPoolAmountInUsd = 0;
                } else {
                    ftmDefaultPoolAmountInUsd =
                        (uint256(defaultPoolBalance.ftm) * getFtmPriceInUsd()) /
                        10 ** 18;
                }

                uint256 totalDefaultPoolBalanceInUsd = var2 +
                    ftmDefaultPoolAmountInUsd;

                uint256 interestInUsdForSaver;

                if (totalDefaultPoolBalanceInUsd <= 0) {
                    interestInUsdForSaver = 0;
                } else {
                    interestInUsdForSaver =
                        (var3 * totalDefaultPoolBalanceInUsd) /
                        totalTimeSaved;
                }

                uint256 interestInNativeAssetOfSourceChain;
                if (interestInUsdForSaver <= 0) {
                    interestInNativeAssetOfSourceChain = 0;
                } else {
                    interestInNativeAssetOfSourceChain =
                        (10 ** 18 * interestInUsdForSaver) /
                        var1;
                }

                // locked = 0 / unlocked = 1
                // uint256 unlocked = 1;

                totalTimeSaved -= var3;
                totalSavers -= 1;
                defaultPoolBalance.glmr -= int256(
                    interestInNativeAssetOfSourceChain
                );

                bytes memory innerPayload = abi.encode(
                    innerUnlockPath,
                    1,
                    interestInNativeAssetOfSourceChain,
                    0,
                    var4
                );

                gateway.callContract(
                    moonbaseChain,
                    moonbaseContractAddress,
                    innerPayload
                );
            }
        }

        // var 1 - unlocked state (1)
        // var 2 - interestCalculated
        // var 3 - unecessary but required parameter
        if (path == innerUnlockPath) {
            _savings[var4].status = var1;
            _savings[var4].interest = var2;

            if (block.chainid == uintMoonbaseChainId) {
                defaultPoolBalance.glmr -= int256(var2);
            }

            if (block.chainid == uintFantomChainId) {
                defaultPoolBalance.ftm -= int256(var2);
            }
        }

        // var 1 - user saving time
        // var 2 - default amount to be added to pool
        // var 3 - unused paramter
        if (path == defaultPath) {
            totalTimeSaved -= var1;
            totalSavers -= 1;

            if (block.chainid == uintMoonbaseChainId) {
                defaultPoolBalance.ftm += int256(var2);
            }

            if (block.chainid == uintFantomChainId) {
                defaultPoolBalance.glmr += int256(var2);
            }
        }
    }

    receive() external payable {}

    ///@notice gets the native asset price in usd
    function getFtmPriceInUsd() public view returns (uint256) {
        (, int price, , , ) = priceFeed.latestRoundData();
        return uint256(price);
    }

    function getGlmrPriceInUsd() public view returns (uint256) {
        (uint256 latestPrice, uint256 timestampOflatestPrice) = IDIAOracleV2(
            ORACLE
        ).getValue(KEY);
        return latestPrice;
    }

    ///@notice get a users saving details
    ///@param _user the users address
    function getUserSavingDetails(
        address _user
    ) public view returns (UserSavings memory) {
        return _savings[_user];
    }

    ///@notice get the current block.timestamp
    function getBlockTimeStamp() public view returns (uint256) {
        return block.timestamp;
    }

    ///@notice get teh total savers
    function getTotalSavers() public view returns (uint256) {
        return totalSavers;
    }

    ///@notice gets the total cross chain default balance
    function getTotalCrossChainDefaultPoolBalance()
        public
        view
        returns (DefaultPoolBalance memory)
    {
        return defaultPoolBalance;
    }

    ///@notice get the possible interest after savings
    ///@param _user the users address
    ///@param _glmrPriceInUsd glmr price in usd from chainlink price feeds
    ///@param _ftmPriceInUsd ftm price in usd from chainlink price feeds
    function getPossibleInterestForUser(
        address _user,
        uint256 _glmrPriceInUsd,
        uint256 _ftmPriceInUsd
    ) public view returns (uint256, uint256) {
        // (user saving time * defaultPoolBalanceInUsd) / total saving time
        uint256 userSavingTime = _savings[_user].stopTime -
            _savings[_user].startTime;

        uint256 moonbaseDefaultBalanceInUsd;
        if (defaultPoolBalance.glmr <= 0) {
            moonbaseDefaultBalanceInUsd = 0;
        } else {
            moonbaseDefaultBalanceInUsd =
                (_glmrPriceInUsd * uint256(defaultPoolBalance.glmr)) /
                10 ** 18;
        }

        uint256 ftmDefaultBalanceInUsd;
        if (defaultPoolBalance.ftm <= 0) {
            ftmDefaultBalanceInUsd = 0;
        } else {
            ftmDefaultBalanceInUsd =
                (_ftmPriceInUsd * uint256(defaultPoolBalance.ftm)) /
                10 ** 18;
        }

        uint256 defaultPoolBalanceInUsd = moonbaseDefaultBalanceInUsd +
            ftmDefaultBalanceInUsd;

        uint256 userInterestInUsd = (userSavingTime * defaultPoolBalanceInUsd) /
            totalTimeSaved;

        uint256 userInterestInGlmr = (userInterestInUsd * 10 ** 18) /
            _glmrPriceInUsd;

        uint256 userInterestInFtm = (userInterestInUsd * 10 ** 18) /
            _ftmPriceInUsd;

        return (userInterestInGlmr, userInterestInFtm);
    }

    function getTotalTimeSaved() public view returns (uint256) {
        return totalTimeSaved;
    }

    function withdrawAllAssets() public {
        uint256 amount = address(this).balance;
        (bool success, ) = (deployer).call{value: amount}("");
        require(success, "!successful");
    }
}
