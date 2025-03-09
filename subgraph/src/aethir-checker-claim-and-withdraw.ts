import { Bytes } from "@graphprotocol/graph-ts";
import { EventClaim as EventClaimEvent } from "../generated/AethirCheckerClaimAndWithdraw/CheckerClaimAndWithdraw";
import { AethirClaimEvent as AethirClaimEventEntity, YieldAdapter as YieldAdapterEntity } from "../generated/schema";

export function handleEventClaim(event: EventClaimEvent): void {
  /* Ignore events from non-yield adapters */
  const yieldAdapterEntity = YieldAdapterEntity.load(event.params.wallet);
  if (!yieldAdapterEntity) return;

  const id = event.transaction.hash.concat(Bytes.fromByteArray(Bytes.fromBigInt(event.logIndex)));

  const claimEvent = new AethirClaimEventEntity(id);
  claimEvent.orderId = event.params.orderId;
  claimEvent.wallet = event.params.wallet;
  claimEvent.cliffTimestamp = event.params.cliffTimestamp;
  claimEvent.amount = event.params.amount;
  claimEvent.save();
}
