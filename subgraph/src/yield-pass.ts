import { Address, BigInt, Bytes, dataSource, ethereum } from "@graphprotocol/graph-ts";
import { ERC20 as ERC20Contract } from "../generated/YieldPass/ERC20";
import { ERC721 as ERC721Contract } from "../generated/YieldPass/ERC721";
import { YieldAdapter as YieldAdapterContract } from "../generated/YieldPass/YieldAdapter";
import {
  Claimed as ClaimedEvent,
  Harvested as HarvestedEvent,
  Minted as MintedEvent,
  Minted1 as MintedEventV1,
  Redeemed as RedeemedEvent,
  Withdrawn as WithdrawnEvent,
  YieldPass as YieldPassContract,
  YieldPassDeployed as YieldPassDeployedEvent,
} from "../generated/YieldPass/YieldPass";
import {
  ERC20 as ERC20Entity,
  ERC721 as ERC721Entity,
  YieldAdapter as YieldAdapterEntity,
  YieldPassMarket as YieldPassMarketEntity,
  YieldPassEvent as YieldPassEventEntity,
  MintedEvent as MintedEventEntity,
  HarvestedEvent as HarvestedEventEntity,
  ClaimedEvent as ClaimedEventEntity,
  RedeemedEvent as RedeemedEventEntity,
  WithdrawnEvent as WithdrawnEventEntity,
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
  adapterEntity.yieldPassMarket = yieldPass;
  adapterEntity.save();
}

export function handleYieldPassDeployed(event: YieldPassDeployedEvent): void {
  const yieldPassMarketEntity = new YieldPassMarketEntity(event.params.yieldPass);
  yieldPassMarketEntity.yieldPassToken = createERC20Entity(event.params.yieldPass).id;
  yieldPassMarketEntity.nodePassToken = createERC721Entity(event.params.nodePass).id;
  yieldPassMarketEntity.nodeToken = createERC721Entity(event.params.nodeToken).id;
  yieldPassMarketEntity.startTime = event.params.startTime;
  yieldPassMarketEntity.expiryTime = event.params.expiryTime;
  yieldPassMarketEntity.adapter = event.params.yieldAdapter;
  yieldPassMarketEntity.nodesDeposited = 0;
  yieldPassMarketEntity.nodesWithdrawn = 0;
  yieldPassMarketEntity.yieldShares = BigInt.zero();
  yieldPassMarketEntity.yieldCumulative = BigInt.zero();
  yieldPassMarketEntity.yieldHarvested = BigInt.zero();
  yieldPassMarketEntity.yieldClaimed = BigInt.zero();
  yieldPassMarketEntity.lastHarvestedEvent = null;
  yieldPassMarketEntity.save();

  createAdapterEntity(event.params.yieldPass, event.params.yieldAdapter);
}

function createYieldPassEventEntity(yieldPass: Address, event: ethereum.Event, type: string): Bytes {
  const id = yieldPass.concat(event.transaction.hash).concat(Bytes.fromByteArray(Bytes.fromBigInt(event.logIndex)));

  const eventEntity = new YieldPassEventEntity(id);
  eventEntity.yieldPassMarket = yieldPass;
  eventEntity.transactionHash = event.transaction.hash;
  eventEntity.timestamp = event.block.timestamp;
  eventEntity.from = event.transaction.from;
  eventEntity.type = type;

  if (type == "Minted") eventEntity.minted = id;
  else if (type == "Harvested") eventEntity.harvested = id;
  else if (type == "Claimed") eventEntity.claimed = id;
  else if (type == "Redeemed") eventEntity.redeemed = id;
  else if (type == "Withdrawn") eventEntity.withdrawn = id;

  eventEntity.save();

  return id;
}

function _handleMinted<T>(event: T): void {
  let yieldPassMarketEntity = YieldPassMarketEntity.load(event.params.yieldPass);
  if (!yieldPassMarketEntity) return;

  yieldPassMarketEntity.nodesDeposited += event.params.nodeTokenIds.length;
  yieldPassMarketEntity.yieldShares = yieldPassMarketEntity.yieldShares.plus(event.params.yieldPassAmount);
  yieldPassMarketEntity.save();

  const eventId = createYieldPassEventEntity(event.params.yieldPass, event, "Minted");
  const mintedEvent = new MintedEventEntity(eventId);
  mintedEvent.account = event instanceof MintedEventV1 ? event.transaction.from : event.params.account;
  mintedEvent.yieldPassRecipient = event.params.yieldPassRecipient;
  mintedEvent.nodePassRecipient = event.params.nodePassRecipient;
  mintedEvent.yieldPassAmount = event.params.yieldPassAmount;
  mintedEvent.nodeToken = event.params.nodeToken;
  mintedEvent.nodeTokenIds = event.params.nodeTokenIds;
  mintedEvent.operators = changetype<Bytes[]>(event.params.operators);
  mintedEvent.save();
}

export function handleMintedV1(event: MintedEventV1): void {
  _handleMinted<MintedEventV1>(event);
}

export function handleMinted(event: MintedEvent): void {
  _handleMinted<MintedEvent>(event);
}

export function handleHarvested(event: HarvestedEvent): void {
  let yieldPassMarketEntity = YieldPassMarketEntity.load(event.params.yieldPass);
  if (!yieldPassMarketEntity) return;

  const eventId = createYieldPassEventEntity(event.params.yieldPass, event, "Harvested");
  const harvestedEvent = new HarvestedEventEntity(eventId);
  harvestedEvent.yieldAmount = event.params.yieldAmount;
  harvestedEvent.save();

  yieldPassMarketEntity.yieldHarvested = yieldPassMarketEntity.yieldHarvested.plus(event.params.yieldAmount);
  yieldPassMarketEntity.yieldCumulative = yieldPassContract.cumulativeYield(event.params.yieldPass);
  yieldPassMarketEntity.lastHarvestedEvent = eventId;
  yieldPassMarketEntity.save();
}

export function handleClaimed(event: ClaimedEvent): void {
  let yieldPassMarketEntity = YieldPassMarketEntity.load(event.params.yieldPass);
  if (!yieldPassMarketEntity) return;

  yieldPassMarketEntity.yieldShares = yieldPassMarketEntity.yieldShares.minus(event.params.yieldPassAmount);
  yieldPassMarketEntity.yieldClaimed = yieldPassMarketEntity.yieldClaimed.plus(event.params.yieldAmount);
  yieldPassMarketEntity.save();

  const eventId = createYieldPassEventEntity(event.params.yieldPass, event, "Claimed");
  const claimedEvent = new ClaimedEventEntity(eventId);
  claimedEvent.account = event.params.account;
  claimedEvent.recipient = event.params.recipient;
  claimedEvent.yieldPassAmount = event.params.yieldPassAmount;
  claimedEvent.yieldToken = event.params.yieldToken;
  claimedEvent.yieldAmount = event.params.yieldAmount;
  claimedEvent.save();
}

export function handleRedeemed(event: RedeemedEvent): void {
  const eventId = createYieldPassEventEntity(event.params.yieldPass, event, "Redeemed");
  const redeemedEvent = new RedeemedEventEntity(eventId);
  redeemedEvent.account = event.params.account;
  redeemedEvent.recipient = event.params.recipient;
  redeemedEvent.nodeToken = event.params.nodeToken;
  redeemedEvent.nodeTokenIds = event.params.nodeTokenIds;
  redeemedEvent.save();
}

export function handleWithdrawn(event: WithdrawnEvent): void {
  let yieldPassMarketEntity = YieldPassMarketEntity.load(event.params.yieldPass);
  if (!yieldPassMarketEntity) return;

  yieldPassMarketEntity.nodesWithdrawn += event.params.nodeTokenIds.length;
  yieldPassMarketEntity.save();

  const eventId = createYieldPassEventEntity(event.params.yieldPass, event, "Withdrawn");
  const withdrawnEvent = new WithdrawnEventEntity(eventId);
  withdrawnEvent.account = event.params.account;
  withdrawnEvent.recipient = event.params.recipient;
  withdrawnEvent.nodeToken = event.params.nodeToken;
  withdrawnEvent.nodeTokenIds = event.params.nodeTokenIds;
  withdrawnEvent.save();
}
