import { Address, dataSource } from "@graphprotocol/graph-ts";
import { ERC20 as ERC20Contract } from "../generated/YieldPass/ERC20";
import { ERC721 as ERC721Contract } from "../generated/YieldPass/ERC721";
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
  ERC721 as ERC721Entity,
  YieldAdapter as YieldAdapterEntity,
  YieldPass as YieldPassEntity,
} from "../generated/schema";

const yieldPassContract = YieldPassContract.bind(dataSource.address());

function createERC20Entity(token: Address): ERC20Entity {
  let erc20Entity = ERC20Entity.load(token);
  if (erc20Entity) return erc20Entity;

  const erc20Contract = ERC20Contract.bind(token);
  const tokenName = erc20Contract.try_name();
  const tokenSymbol = erc20Contract.try_symbol();
  const tokenDecimals = erc20Contract.try_decimals();

  erc20Entity = new ERC20Entity(token);
  erc20Entity.name = tokenName.reverted ? "Unnamed Token" : tokenName.value;
  erc20Entity.symbol = tokenSymbol.reverted ? "UNK" : tokenSymbol.value;
  erc20Entity.decimals = tokenDecimals.reverted ? 18 : tokenDecimals.value;
  erc20Entity.save();

  return erc20Entity;
}

function createERC721Entity(token: Address): ERC721Entity {
  let erc721Entity = ERC721Entity.load(token);
  if (erc721Entity) return erc721Entity;

  const erc721Contract = ERC721Contract.bind(token);
  const tokenName = erc721Contract.try_name();
  const tokenSymbol = erc721Contract.try_symbol();

  erc721Entity = new ERC721Entity(token);
  erc721Entity.name = tokenName.reverted ? "Unnamed Token" : tokenName.value;
  erc721Entity.symbol = tokenSymbol.reverted ? "UNK" : tokenSymbol.value;
  erc721Entity.save();

  return erc721Entity;
}

function createAdapterEntity(yieldPass: Address, adapter: Address): void {
  const adapterContract = YieldAdapterContract.bind(adapter);

  const adapterEntity = new YieldAdapterEntity(adapter);
  adapterEntity.name = adapterContract.name();
  adapterEntity.yieldToken = createERC20Entity(adapterContract.token()).id;
  adapterEntity.yieldPass = yieldPass;
  adapterEntity.save();
}

export function handleYieldPassDeployed(event: YieldPassDeployedEvent): void {
  const yieldPassEntity = new YieldPassEntity(event.params.yieldPass);
  yieldPassEntity.yieldPassToken = createERC20Entity(event.params.yieldPass).id;
  yieldPassEntity.nodePassToken = createERC721Entity(event.params.nodePass).id;
  yieldPassEntity.nftToken = createERC721Entity(event.params.token).id;
  yieldPassEntity.startTime = event.params.startTime;
  yieldPassEntity.expiryTime = event.params.expiryTime;
  yieldPassEntity.adapter = event.params.yieldAdapter;
  yieldPassEntity.save();

  createAdapterEntity(event.params.yieldPass, event.params.yieldAdapter);
}

export function handleClaimed(event: ClaimedEvent): void {}

export function handleHarvested(event: HarvestedEvent): void {}

export function handleMinted(event: MintedEvent): void {}

export function handleRedeemed(event: RedeemedEvent): void {}

export function handleWithdrawn(event: WithdrawnEvent): void {}
