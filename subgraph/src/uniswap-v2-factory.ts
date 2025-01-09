import { PairCreated as PairCreatedEvent } from "../generated/UniswapV2Factory/UniswapV2Factory";
import { UniswapV2Pair as UniswapV2PairEntity, YieldPass as YieldPassEntity } from "../generated/schema";

export function handlePairCreated(event: PairCreatedEvent): void {
  let yieldPassEntity = YieldPassEntity.load(event.params.token0);
  if (!yieldPassEntity) yieldPassEntity = YieldPassEntity.load(event.params.token1);
  if (!yieldPassEntity) return;

  yieldPassEntity.pair = event.params.pair;
  yieldPassEntity.save();

  const pairEntity = new UniswapV2PairEntity(event.params.pair);
  pairEntity.token0 = event.params.token0;
  pairEntity.token1 = event.params.token1;
  pairEntity.yieldPass = yieldPassEntity.id;
  pairEntity.save();
}
