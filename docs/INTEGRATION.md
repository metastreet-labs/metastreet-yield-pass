# Yield Adapters

Yield adapters facilitate assigning NFTs to operators, harvesting their yield,
and withdrawing them.

Yield adapters are implemented with the [`IYieldAdapter`](../src/interfaces/IYieldAdapter.sol) interface.

Yield adapters implement four main hooks in this interface:

* `setup()` to assign NFTs to operators
* `harvest()` to periodically harvest yield
* `claim()` to claim yield tokens
* `initiateWidthraw()` and `withdraw()` to initiate and complete the withdrawal of an NFT
