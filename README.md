<table align="center">
  <tr>
    <td align="center">
      <img src="imgs/Cod3x_Logo.png" alt="Cod3x Logo" style="width: 90px;">
    </td>
    <td align="center">
      <font size="+4"><b>Cod3x USD</b></font>
    </td>
  </tr>
</table>


<br>

<p align="center">Cod3x-USD (cdxUSD) is the native Cod3x overcollateralized stablecoin integrated into <a href="https://github.com/Cod3x-Labs/Cod3x-Lend" style="color: #a77dff">Cod3x lend</a> market, multichain using <a href="https://layerzero.network/" style="color: #a77dff">LayerZero</a> and with a new innovative interest rate <a href="https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4844212" style="color: #a77dff">PID controle system</a>.
</p>
<p align="center">
    <img alt="LayerZero" src="imgs/Cod3x_Super_App.png"/>
</p>

## Quickstart

#### Installing dependencies

```bash
yarn install
```

#### Compiling your contracts

This project supports both `hardhat` and `forge` compilation. By default, the `compile` command will execute both:

```bash
yarn compile
```

#### Running tests

```bash
yarn test
```

## Deploying Contracts

Set up deployer wallet/account:

- Rename `.env.example` -> `.env`
- Choose your preferred means of setting up your deployer wallet/account:

```
MNEMONIC="test test test test test test test test test test test junk"
or...
PRIVATE_KEY="0xabc...def"
```

- Fund this address with the corresponding chain's native tokens you want to deploy to.

To deploy your contracts to your desired blockchains, run the following command in your project's folder:

```bash
npx hardhat lz:deploy
```

More information about available CLI arguments can be found using the `--help` flag:

```bash
npx hardhat lz:deploy --help
```

<br>

<p align="center">
  Join our community on <a href="https://discord.gg/ks3XVH3yg2" style="color: #a77dff">Discord</a> | Follow us on <a href="https://twitter.com/DeFiCod3x" style="color: #a77dff">Twitter</a>
</p>
