from brownie import CrossSave, accounts, network
from web3 import Web3


def main():
    get_ftm_price()


def deploy():
    acct = accounts.load("test3")

    # MOONBASE CHAIN TESTNET - 0xfeB60Aee72eAc83baaAaD9A15829A64536676389
    axelar_gateway_moonbase = "0x5769D84DD62a6fD969856c75c7D321b84d455929"
    axelar_gasreceiver_moonbase = "0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6"
    oracle_address = "0xe23D8713Aa3A0A2C102AF772D2467064821b8d46"

    # FANTOM CHAIN - 0x70D6779bF576e64F7048eFb3Ee189d47Dc22De2A
    axelar_gateway_fantom = "0x97837985Ec0494E7b9C71f5D3f9250188477ae14"
    axelar_gasreceiver_fantom = "0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6"
    ftm_usd_price_feed = "0xe04676B9A9A2973BCb0D1478b5E1E9098BBB7f3D"

    minimum_saving_time = 300  # 5 minutes
    minimum_saving_amount = Web3.toWei("0.0001", "ether")

    # CrossSave.deploy(
    #     axelar_gateway_moonbase,
    #     axelar_gasreceiver_moonbase,
    #     oracle_address,
    #     minimum_saving_time,
    #     minimum_saving_amount,
    #     {"from": acct},
    # )

    CrossSave.deploy(
        axelar_gateway_fantom,
        axelar_gasreceiver_fantom,
        ftm_usd_price_feed,
        minimum_saving_time,
        minimum_saving_amount,
        {"from": acct},
    )


def get_glmr_price():
    price = CrossSave[-1].getGlmrPriceInUsd()
    print(f"The price is {price}")


def get_ftm_price():
    price = CrossSave[-1].getFtmPriceInUsd()
    print(f"The price is {price}")


def update_contract_addresses():
    acct = accounts.load("test3")

    moonbase_contract_address = "0xfeB60Aee72eAc83baaAaD9A15829A64536676389".encode(
        "utf-8"
    )
    fantom_fantom_address = "0x70D6779bF576e64F7048eFb3Ee189d47Dc22De2A".encode("utf-8")
    CrossSave[-1].updateStringContractAddresses(
        moonbase_contract_address, fantom_fantom_address, {"from": acct}
    )


def get_total_time_saved():
    total_time_Saved = CrossSave[-1].totalTimeSaved()
    print(f"The total time saved on {network.show_active()} is {total_time_Saved}")


def get_user_saving_details():
    address = "0x391c3a9806945e3f5953F718BF8885F72a0D367b"
    user_details = CrossSave[-1].getUserSavingDetails(address)
    print(f"The User savings details for {address} is {user_details}")


def get_blocktimestamp():
    address = None
    current_timestamp = CrossSave[-1].getUserSavingDetails()
    print(f"The current time stamp for {network.show_active()} is {current_timestamp}")


def get_total_savers():
    total_savers = CrossSave[-1].getTotalSavers()
    print(f"The current total savers are {total_savers} on {network.show_active()}")


def get_total_cross_chain_default_balance():
    total_default_balance = CrossSave[-1].getTotalCrossChainDefaultPoolBalance()
    print(
        f"The current total cross chain default balance {total_default_balance} on {network.show_active()}"
    )


def withdraw_all_assets():
    acct = accounts.load("test3")
    total_savers = CrossSave[-1].withdrawAllAssets({"from": acct})


def get_user_possible_interest():
    user = "0x391c3a9806945e3f5953F718BF8885F72a0D367b"
    avax_usd_price = 1342891879
    ftm_usd_price = 24023930
    user_interest = CrossSave[-1].getPossibleInterestForUser(
        user, avax_usd_price, ftm_usd_price
    )

    print(f"The user possible interest is {user_interest}")
