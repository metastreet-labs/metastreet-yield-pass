import { Address, BigInt, Bytes, dataSource, ethereum } from "@graphprotocol/graph-ts";
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
  yieldPassEntity.nodesDeposited = 0;
  yieldPassEntity.nodesWithdrawn = 0;
  yieldPassEntity.yieldShares = BigInt.zero();
  yieldPassEntity.yieldHarvested = BigInt.zero();
  yieldPassEntity.yieldClaimed = BigInt.zero();
  yieldPassEntity.save();

  createAdapterEntity(event.params.yieldPass, event.params.yieldAdapter);
}

function createYieldPassEventEntity(yieldPass: Address, event: ethereum.Event, type: string): Bytes {
  const id = yieldPass.concat(event.transaction.hash).concat(Bytes.fromByteArray(Bytes.fromBigInt(event.logIndex)));

  const eventEntity = new YieldPassEventEntity(id);
  eventEntity.yieldPass = yieldPass;
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

export function handleMinted(event: MintedEvent): void {
  let yieldPassEntity = YieldPassEntity.load(event.params.yieldPass);
  if (!yieldPassEntity) return;

  yieldPassEntity.nodesDeposited += event.params.tokenIds.length;
  yieldPassEntity.yieldShares = yieldPassEntity.yieldShares.plus(event.params.yieldPassAmount);
  yieldPassEntity.save();

  const eventId = createYieldPassEventEntity(event.params.yieldPass, event, "Minted");
  const mintedEvent = new MintedEventEntity(eventId);
  mintedEvent.yieldPassRecipient = event.params.yieldPassRecipient;
  mintedEvent.nodePassRecipient = event.params.nodePassRecipient;
  mintedEvent.yieldPassAmount = event.params.yieldPassAmount;
  mintedEvent.token = event.params.token;
  mintedEvent.tokenIds = event.params.tokenIds;
  mintedEvent.operators = changetype<Bytes[]>(event.params.operators);
  mintedEvent.save();
}

export function handleHarvested(event: HarvestedEvent): void {
  let yieldPassEntity = YieldPassEntity.load(event.params.yieldPass);
  if (!yieldPassEntity) return;

  yieldPassEntity.yieldHarvested = yieldPassEntity.yieldHarvested.plus(event.params.amount);
  yieldPassEntity.save();

  const eventId = createYieldPassEventEntity(event.params.yieldPass, event, "Harvested");
  const harvestedEvent = new HarvestedEventEntity(eventId);
  harvestedEvent.yieldAmount = event.params.amount;
  harvestedEvent.save();
}

export function handleClaimed(event: ClaimedEvent): void {
  let yieldPassEntity = YieldPassEntity.load(event.params.yieldPass);
  if (!yieldPassEntity) return;

  yieldPassEntity.yieldShares = yieldPassEntity.yieldShares.minus(event.params.yieldPassAmount);
  yieldPassEntity.yieldClaimed = yieldPassEntity.yieldClaimed.plus(event.params.yieldAmount);
  yieldPassEntity.save();

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
  redeemedEvent.token = event.params.token;
  redeemedEvent.tokenIds = event.params.tokenIds;
  redeemedEvent.save();
}

export function handleWithdrawn(event: WithdrawnEvent): void {
  let yieldPassEntity = YieldPassEntity.load(event.params.yieldPass);
  if (!yieldPassEntity) return;

  yieldPassEntity.nodesWithdrawn += event.params.tokenIds.length;
  yieldPassEntity.save();

  const eventId = createYieldPassEventEntity(event.params.yieldPass, event, "Withdrawn");
  const withdrawnEvent = new WithdrawnEventEntity(eventId);
  withdrawnEvent.account = event.params.account;
  withdrawnEvent.recipient = event.params.recipient;
  withdrawnEvent.token = event.params.token;
  withdrawnEvent.tokenIds = event.params.tokenIds;
  withdrawnEvent.save();
}
