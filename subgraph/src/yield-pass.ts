import { Address, dataSource } from "@graphprotocol/graph-ts";
import { ERC20 as ERC20Contract } from "../generated/YieldPass/ERC20";
import { YieldAdapter as YieldAdapterContract } from "../generated/YieldPass/YieldAdapter";
import {
  Claimed as ClaimedEvent,
  Harvested as HarvestedEvent,
  Minted as MintedEvent,
  Redeemed as RedeemedEvent,
  Withdrawn as WithdrawnEvent,
  YieldPass as YieldPassContract,
  YieldPassDeployed as YieldPassDeployedEvent,
} from "../generated/YieldPass/YieldPass";
import {
  ERC20 as ERC20Entity,
  YieldAdapter as YieldAdapterEntity,
  YieldPassToken as YieldPassTokenEntity,
} from "../generated/schema";

const yieldPassContract = YieldPassContract.bind(dataSource.address());

function createAdapterEntity(yieldPassToken: Address, adapter: Address): void {
  const adapterContract = YieldAdapterContract.bind(adapter);

  const erc20Address = adapterContract.token();

  const adapterEntity = new YieldAdapterEntity(adapter);
  adapterEntity.yieldPassToken = yieldPassToken;
  adapterEntity.token = erc20Address;
  adapterEntity.name = adapterContract.name();
  adapterEntity.save();

  const erc20Contract = ERC20Contract.bind(erc20Address);
  const tokenName = erc20Contract.try_name();
  const tokenSymbol = erc20Contract.try_symbol();
  const tokenDecimals = erc20Contract.try_decimals();

  let erc20Entity = ERC20Entity.load(erc20Address);
  if (!erc20Entity) {
    erc20Entity = new ERC20Entity(erc20Address);
    erc20Entity.name = tokenName.reverted ? "Unnamed Token" : tokenName.value;
    erc20Entity.symbol = tokenSymbol.reverted ? "UNK" : tokenSymbol.value;
    erc20Entity.decimals = tokenDecimals.reverted ? 18 : tokenDecimals.value;
    erc20Entity.save();
  }
}

export function handleYieldPassDeployed(event: YieldPassDeployedEvent): void {
  const yieldPassTokenEntity = new YieldPassTokenEntity(event.params.yieldPass);
  yieldPassTokenEntity.startTime = event.params.startTime;
  yieldPassTokenEntity.expiryTime = event.params.expiryTime;
  yieldPassTokenEntity.token = event.params.token;
  yieldPassTokenEntity.nodePass = event.params.nodePass;
  yieldPassTokenEntity.adapter = event.params.yieldAdapter;
  yieldPassTokenEntity.save();

  createAdapterEntity(event.params.yieldPass, event.params.yieldAdapter);
}

export function handleClaimed(event: ClaimedEvent): void {}

export function handleHarvested(event: HarvestedEvent): void {}

export function handleMinted(event: MintedEvent): void {}

export function handleRedeemed(event: RedeemedEvent): void {}

export function handleWithdrawn(event: WithdrawnEvent): void {}
