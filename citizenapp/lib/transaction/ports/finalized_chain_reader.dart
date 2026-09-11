import 'dart:typed_data';

/// Exact finalized block bytes required by CitizenApp-owned event decoders.
final class AppFinalizedBlockData {
  AppFinalizedBlockData({
    required this.blockHash,
    required this.blockNumber,
    required Uint8List runtimeMetadata,
    required List<Uint8List> extrinsics,
    required Uint8List systemEvents,
  })  : runtimeMetadata = Uint8List.fromList(runtimeMetadata),
        extrinsics = List<Uint8List>.unmodifiable(
          extrinsics.map(Uint8List.fromList),
        ),
        systemEvents = Uint8List.fromList(systemEvents);

  final String blockHash;
  final int blockNumber;
  final Uint8List runtimeMetadata;
  final List<Uint8List> extrinsics;
  final Uint8List systemEvents;
}

/// Read-only exact-finality port; storage keys and SCALE business decoding stay
/// in CitizenApp. Part 3 supplies the CitizenSDK-backed implementation.
abstract interface class FinalizedChainReader {
  Future<AppFinalizedBlockData> readFinalizedBlock(int blockNumber);
}
