/// Metadata key attached to a ChatResult yielded mid-stream to surface an
/// in-progress (still streaming) model tool call before it completes.
///
/// The payload is a `Map<String, String>` with the keys `id`, `name` and
/// `args`, where `args` holds the (possibly incomplete) JSON arguments
/// accumulated so far. An empty `name` signals that the tool call was never
/// finalized and should be retracted by the consumer.
const String kLiveToolCallMetadataKey = 'live_tool_call';

/// Helper to build the [kLiveToolCallMetadataKey] payload.
Map<String, String> buildLiveToolCallMetadata({
  required String id,
  required String name,
  required String args,
}) =>
    <String, String>{
      'id': id,
      'name': name,
      'args': args,
    };
