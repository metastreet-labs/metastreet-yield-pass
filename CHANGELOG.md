* YieldPass v1.2 - 02/12/2025
    * Add `yieldPassFactory()` getter to YieldPassToken and NodePassToken.
    * Add `yieldPass()` getter to NodePassToken.
    * Add simpler `mint()` overload.

* XaiYieldAdapter v1.2 - 02/04/2025
    * Update with IYieldAdapter interface changes.
    * Implement node transfer lock logic.
    * Rename `yieldPass()` getter to `yieldPassFactory()`.

* AethirYieldAdapter v1.2 - 02/04/2025
    * Update with IYieldAdapter interface changes.
    * Implement node transfer lock logic.
    * Rename `yieldPass()` getter to `yieldPassFactory()`.

* YieldPass v1.1 - 02/04/2025
    * Move node transfer lock logic to yield adapters.
    * Refactor `redeem()`, `withdraw()` APIs in IYieldPass.
    * Refactor internal `setup()`, `harvest()` APIs in IYieldAdapter.
    * Improve amount and token parameter naming in IYieldPass.
    * Add `totalSupply()` getter to NodePassToken.
    * Add `account` parameter to Minted event.

* AethirYieldAdapter v1.1 - 01/13/2025
    * Add `redelegate()` admin API.

* XaiYieldAdapter v1.1 - 01/13/2025
    * Update with XAI node license staking changes.

* XaiYieldAdapter v1.0 - 12/17/2024
    * Initial release.

* AethirYieldAdapter v1.0 - 12/17/2024
    * Initial release.

* YieldPassUtils v1.0 - 12/17/2024
    * Initial release.

* YieldPass v1.0 - 12/17/2024
    * Initial release.
