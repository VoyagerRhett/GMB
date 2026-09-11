# CitizenApp transaction history

This directory owns CitizenApp's business transaction history. It is not a
CitizenSDK implementation and is never read or migrated by CitizenSDK.

- `data/` stores the App's Isar projection, including destination, amount,
  remark, direction and display status.
- `chain/` reads finalized chain data and decodes CitizenChain business events
  with the exact block metadata.
- `application/` correlates product-neutral SDK execution facts with the App's
  existing records by transaction hash.
- `presentation/` owns the transaction tab/page and refresh behavior.

Business code constructs CitizenChain calls in
`../onchain-transaction/` and invokes only the SDK-neutral ports in `../ports/`.
Part 3 will bind those ports to CitizenSDK. There is no old-store migration,
compatibility reader, alias, fallback or dual-write path.
