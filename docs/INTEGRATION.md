# Airdrop Adapters

Airdrop adapters facilitate checking the claim status of an airdrop and
claiming airdrop tokens for an NFT. Since there is no standardization of ERC20
airdrops for NFTs, each airdrop project must have a corresponding airdrop
adapter implementation to support claiming the actual airdrop tokens for an
airdrop pass.

Airdrop pass requires the following three preconditions to support tokenizing
airdrops for an NFT:

* Airdrop is an ERC20 of uniform amount per NFT token ID (not per wallet)
* Airdrop can be claimed by a [delegate.xyz](https://delegate.xyz/) delegate
* Airdrop can be checked and claimed on-chain

Airdrop adapters are implemented with the [`IAirdropAdapter`](../src/interfaces/IAirdropAdapter.sol) interface.

In a nutshell, an airdrop adapter must support checking if airdrop tokens have
been already claimed for an NFT with the `isClaimable(uint256 tokenId) -> (bool)`
function, and must support constructing the claim calldata for an NFT with the
`claimCalldata(uint256 tokenId) -> (address, bytes)` function.
