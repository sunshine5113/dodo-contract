/*

    Copyright 2020 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

import BigNumber from 'bignumber.js';
import Web3 from 'web3';
import { Contract } from 'web3-eth-contract';

import * as contracts from './Contracts';
import { decimalStr, mweiStr, MAX_UINT256 } from './Converter';
import { EVM, getDefaultWeb3 } from './EVM';
import * as log from './Log';

BigNumber.config({
  EXPONENTIAL_AT: 1000,
  DECIMAL_PLACES: 80,
});


export class ProxyContext {
  EVM: EVM;
  Web3: Web3;
  DODOProxyV2: Contract;
  DVMFactory: Contract;
  DPPFactory: Contract;
  CPFactory: Contract;
  DODOApprove: Contract;
  DODOCalleeHelper: Contract;
  DODOSellHelper: Contract;

  //token
  DODO: Contract;
  USDT: Contract;
  WETH: Contract;

  Deployer: string;
  Maintainer: string;
  SpareAccounts: string[];

  constructor() { }

  async init(weth:string) {
    this.EVM = new EVM();
    this.Web3 = getDefaultWeb3();
    const allAccounts = await this.Web3.eth.getAccounts();
    this.Deployer = allAccounts[0];
    this.Maintainer = allAccounts[1];
    this.SpareAccounts = allAccounts.slice(2, 10);

    this.WETH = contracts.getContractWithAddress(contracts.WETH_CONTRACT_NAME, weth);

    var cloneFactory = await contracts.newContract(
      contracts.CLONE_FACTORY_CONTRACT_NAME
    );
    var dvmTemplate = await contracts.newContract(contracts.DVM_NAME)
    var dppTemplate = await contracts.newContract(contracts.DPP_NAME)
    var cpTemplate = await contracts.newContract(contracts.CROWD_POOLING_NAME)
    var dvmAdminTemplate = await contracts.newContract(contracts.DVM_ADMIN_NAME)
    var dppAdminTemplate = await contracts.newContract(contracts.DPP_ADMIN_NAME)
    var feeRateModelTemplate = await contracts.newContract(contracts.FEE_RATE_MODEL_NAME)
    var permissionManagerTemplate = await contracts.newContract(contracts.PERMISSION_MANAGER_NAME)
    var vauleSource = await contracts.newContract(contracts.EXTERNAL_VALUE_NAME)
    var defaultGasSource = await contracts.newContract(contracts.EXTERNAL_VALUE_NAME)
    await defaultGasSource.methods.init(this.Deployer,MAX_UINT256).send(this.sendParam(this.Deployer));

    this.DVMFactory = await contracts.newContract(contracts.DVM_FACTORY_NAME,
      [
        cloneFactory.options.address,
        dvmTemplate.options.address,
        dvmAdminTemplate.options.address,
        feeRateModelTemplate.options.address,
        permissionManagerTemplate.options.address,
        defaultGasSource.options.address,
        this.Deployer,
        feeRateModelTemplate.options.address,
        permissionManagerTemplate.options.address
       ]
    )

    this.DODOApprove = await contracts.newContract(
      contracts.SMART_APPROVE
    );


    this.DPPFactory = await contracts.newContract(contracts.DPP_FACTORY_NAME,
      [
        cloneFactory.options.address,
        dppTemplate.options.address,
        dppAdminTemplate.options.address,
        feeRateModelTemplate.options.address,
        permissionManagerTemplate.options.address,
        vauleSource.options.address,
        defaultGasSource.options.address,
        this.DODOApprove.options.address
      ]
    )

    this.CPFactory = await contracts.newContract(contracts.CROWD_POOLING_FACTORY,
      [
        cloneFactory.options.address,
        cpTemplate.options.address,
        this.DVMFactory.options.address,
        feeRateModelTemplate.options.address,
        this.Deployer,
        feeRateModelTemplate.options.address,
        permissionManagerTemplate.options.address,
        defaultGasSource.options.address
      ]  
    )

    this.DODOSellHelper = await contracts.newContract(
      contracts.DODO_SELL_HELPER
    );

    this.DODOProxyV2 = await contracts.newContract(contracts.DODO_PROXY_NAME,
      [
        this.DVMFactory.options.address,
        this.DPPFactory.options.address,
        this.CPFactory.options.address,
        this.WETH.options.address,
        this.DODOApprove.options.address,
        this.DODOSellHelper.options.address
      ]
    );

    await this.DODOProxyV2.methods.initOwner(this.Deployer).send(this.sendParam(this.Deployer));
    await this.DODOApprove.methods.init(this.Deployer,this.DODOProxyV2.options.address).send(this.sendParam(this.Deployer));

    this.DODO = await contracts.newContract(
      contracts.MINTABLE_ERC20_CONTRACT_NAME,
      ["DODO Token", "DODO", 18]
    );
    this.USDT = await contracts.newContract(
      contracts.MINTABLE_ERC20_CONTRACT_NAME,
      ["USDT Token", "USDT", 6]
    );

    this.DODOCalleeHelper = await contracts.newContract(
      contracts.DODO_CALLEE_HELPER_NAME,
      [this.WETH.options.address]
    )

    console.log(log.blueText("[Init DVM context]"));
  }

  sendParam(sender, value = "0") {
    return {
      from: sender,
      gas: process.env["COVERAGE"] ? 10000000000 : 7000000,
      gasPrice: mweiStr("1000"),
      value: decimalStr(value),
    };
  }

  async mintTestToken(to: string, token: Contract, amount: string) {
    await token.methods.mint(to, amount).send(this.sendParam(this.Deployer));
  }

  async approveProxy(account: string) {
    await this.DODO.methods
      .approve(this.DODOApprove.options.address, MAX_UINT256)
      .send(this.sendParam(account));
    await this.USDT.methods
      .approve(this.DODOApprove.options.address, MAX_UINT256)
      .send(this.sendParam(account));
    await this.WETH.methods
      .approve(this.DODOApprove.options.address, MAX_UINT256)
      .send(this.sendParam(account));
  }
}

export async function getProxyContext(weth:string): Promise<ProxyContext> {
  var context = new ProxyContext();
  await context.init(weth);
  return context;
}
