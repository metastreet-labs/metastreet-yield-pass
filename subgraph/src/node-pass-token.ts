import { Bytes, dataSource } from "@graphprotocol/graph-ts";
import { NodePassTokenOwnership as NodePassTokenOwnershipEntity } from "../generated/schema";
import { Transfer as TransferEvent } from "../generated/templates/NodePassToken/NodePassToken";

const nodePassToken = dataSource.address();

export function handleTransfer(event: TransferEvent): void {
  const id = nodePassToken.concat(Bytes.fromByteArray(Bytes.fromBigInt(event.params.tokenId)));

  let ownershipEntity = NodePassTokenOwnershipEntity.load(id);

  if (!ownershipEntity) {
    ownershipEntity = new NodePassTokenOwnershipEntity(id);
    ownershipEntity.tokenId = event.params.tokenId;
    ownershipEntity.nodePassToken = nodePassToken;
  }

  ownershipEntity.owner = event.params.to;

  ownershipEntity.save();
}
