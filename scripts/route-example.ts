import { AlphaRouter, ChainId } from "@uniswap/smart-order-router";
import { Token, CurrencyAmount, TradeType, Percent } from "@uniswap/sdk-core";
import { ethers } from "ethers";

async function main() {
  const V3_SWAP_ROUTER_ADDRESS = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45";
  const MY_ADDRESS = "0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B";
  const web3Provider = new ethers.providers.InfuraProvider(
    "mainnet",
    "737bcb5393b146d7870be2f68a7cea9c"
  );

  const router = new AlphaRouter({ chainId: 1, provider: web3Provider });

  const WETH = new Token(
    1,
    "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    18,
    "WETH",
    "Wrapped Ether"
  );

  const LUSD = new Token(
    ChainId.MAINNET,
    "0x5f98805A4E8be255a32880FDeC7F6728C6568bA0",
    18,
    "LUSD",
    "LUSD Stablecoin"
  );

  const wethAmount = CurrencyAmount.fromRawAmount(WETH, 1e22);

  const route = await router.route(wethAmount, LUSD, TradeType.EXACT_INPUT, {
    recipient: MY_ADDRESS,
    slippageTolerance: new Percent(5, 100),
    deadline: 100,
  });

  console.log(route)

  // console.log(`Quote Exact In: ${route.quote.toFixed(2)}`);
  // console.log(`Gas Adjusted Quote In: ${route.quoteGasAdjusted.toFixed(2)}`);
  // console.log(`Gas Used USD: ${route.estimatedGasUsedUSD.toFixed(6)}`);

  // const transaction = {
  //   data: route.methodParameters.calldata,
  //   to: V3_SWAP_ROUTER_ADDRESS,
  //   value: BigNumber.from(route.methodParameters.value),
  //   from: MY_ADDRESS,
  //   gasPrice: BigNumber.from(route.gasPriceWei),
  // };

  // await web3Provider.sendTransaction(transaction);
}

main().catch((error) => console.error(error));
