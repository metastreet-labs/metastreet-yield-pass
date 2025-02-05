# Yield Adapters

Yield adapters facilitate assigning node NFTs to operators, harvesting yield,
claiming yield tokens, and withdrawing node NFTs.

Yield adapters are implemented with the [`IYieldAdapter`](../src/interfaces/IYieldAdapter.sol) interface.

Yield adapters implement four main hooks in this interface:

* `setup()` to assign node NFTs to operators
* `harvest()` to periodically harvest yield
* `claim()` to claim yield tokens
* `redeem()` and `withdraw()` to redeem and withdraw node NFTs
