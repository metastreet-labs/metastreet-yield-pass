import { PairCreated as PairCreatedEvent } from "../generated/UniswapV2Factory/UniswapV2Factory";
import { UniswapV2Pair as UniswapV2PairEntity, YieldPassMarket as YieldPassMarketEntity } from "../generated/schema";

export function handlePairCreated(event: PairCreatedEvent): void {
  let yieldPassMarketEntity = YieldPassMarketEntity.load(event.params.token0);
  if (!yieldPassMarketEntity) yieldPassMarketEntity = YieldPassMarketEntity.load(event.params.token1);
  if (!yieldPassMarketEntity) return;

  yieldPassMarketEntity.pair = event.params.pair;
  yieldPassMarketEntity.save();

  const pairEntity = new UniswapV2PairEntity(event.params.pair);
  pairEntity.token0 = event.params.token0;
  pairEntity.token1 = event.params.token1;
  pairEntity.yieldPassMarket = yieldPassMarketEntity.id;
  pairEntity.save();
}
