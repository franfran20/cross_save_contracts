import {
  AxelarQueryAPI,
  EvmChain,
  GasToken,
} from "@axelar-network/axelarjs-sdk";

const sdk = new AxelarQueryAPI({
  environment: "testnet",
});

const savingsGas = 120000;

const unlockSavingsGas = 400000;

const defaultGas = 80000;

async function main() {
  // BNB CHAIN
  const gasFeeForSavingsOnBnb = await sdk.estimateGasFee(
    EvmChain.MOONBEAM,
    EvmChain.FANTOM,
    GasToken.GLMR,
    savingsGas
  );

  console.log(
    "Gas Fee For Savings From MOONBASE TO FANTOM: ",
    gasFeeForSavingsOnBnb
  );

  const gasFeeForSavingsUnlockOnBnb = await sdk.estimateGasFee(
    EvmChain.MOONBEAM,
    EvmChain.FANTOM,
    GasToken.GLMR,
    unlockSavingsGas
  );

  console.log(
    "Gas Fee For Unlocking Savings From MOONBASE TO FANTOM: ",
    gasFeeForSavingsUnlockOnBnb
  );

  const gasFeeForSavingsDefaultingOnSavingsForBNB = await sdk.estimateGasFee(
    EvmChain.MOONBEAM,
    EvmChain.FANTOM,
    GasToken.GLMR,
    defaultGas
  );

  console.log(
    "Gas Fee For Defaulting On Savings From BNB: ",
    gasFeeForSavingsDefaultingOnSavingsForBNB
  );

  //FANTOM CHAIN
  const gasFeeForSavingsOnFantom = await sdk.estimateGasFee(
    EvmChain.FANTOM,
    EvmChain.MOONBEAM,
    GasToken.FTM,
    savingsGas
  );

  console.log(
    "Gas Fee For Savings From Fantom To Moonbeam: ",
    gasFeeForSavingsOnFantom
  );

  const gasFeeForSavingsUnlockOnFantom = await sdk.estimateGasFee(
    EvmChain.FANTOM,
    EvmChain.MOONBEAM,
    GasToken.FTM,
    unlockSavingsGas
  );

  console.log(
    "Gas Fee For Unlocking Savings From Fantom To Moonbeam: ",
    gasFeeForSavingsUnlockOnFantom
  );

  const gasFeeForSavingsDefaultingOnSavingsForFantom = await sdk.estimateGasFee(
    EvmChain.FANTOM,
    EvmChain.MOONBEAM,
    GasToken.FTM,
    defaultGas
  );

  console.log(
    "Gas Fee For Defaulting On Savings From Fantom To Moonbeam: ",
    gasFeeForSavingsDefaultingOnSavingsForFantom
  );
}

main();
