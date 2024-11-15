import { PairCreated as PairCreatedEvent } from "../generated/UniswapV2Factory/UniswapV2Factory";
import { UniswapV2Pair as UniswapV2PairEntity, YieldPassToken as YieldPassTokenEntity } from "../generated/schema";

export function handlePairCreated(event: PairCreatedEvent): void {
  let yieldPassTokenEntity = YieldPassTokenEntity.load(event.params.token0);
  if (!yieldPassTokenEntity) yieldPassTokenEntity = YieldPassTokenEntity.load(event.params.token1);
  if (!yieldPassTokenEntity) return;

  yieldPassTokenEntity.pair = event.params.pair;
  yieldPassTokenEntity.save();

  const pairEntity = new UniswapV2PairEntity(event.params.pair);
  pairEntity.token0 = event.params.token0;
  pairEntity.token1 = event.params.token1;
  pairEntity.yieldPassToken = yieldPassTokenEntity.id;
  pairEntity.save();
}
