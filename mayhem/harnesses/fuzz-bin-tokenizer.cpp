// libFuzzer harness for the binary tokenizer.
//
// The in-memory BinTokenizer constructor parses a byte blob (a tokenizer.bin loaded from disk or an
// app bundle, or handed to the model loaders from memory). This harness models the blob a file reader
// can really get: a well-formed token stream (each fuzz-chosen token written with the format's own
// length prefix) that a short read may have cut off. The last input byte is that cut: values below 8
// drop that many bytes from the end of the stream, anything else leaves it whole. Raw bytes would not
// do: a length-prefixed blob is almost never well-formed after a mutation, so nearly every input
// would be a truncated one, and libFuzzer's default seed ("\n") alone would end every run at once.
//
// The blob also feeds a text_to_tokens / tokens_to_text round trip. Exceptions are the library's
// documented failure mode, so they are caught and ignored; only sanitizer errors fail the run.

#include <fuzzer/FuzzedDataProvider.h>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <exception>
#include <string>
#include <vector>

#include "bin-tokenizer.h"

namespace {
constexpr uint8_t kTruncationLimit = 8;
constexpr size_t kMaxTokenSize = 300;
constexpr size_t kMaxTextSize = 128;

// The format BinTokenizer reads: 0 is an empty token, 1..127 the byte count, else two bytes
// (128 + count % 128, count / 128).
void append_token(std::vector<uint8_t> &blob, const std::vector<uint8_t> &token) {
  const size_t count = token.size();
  if (count == 0) {
    blob.push_back(0);
  } else if (count < 128) {
    blob.push_back(static_cast<uint8_t>(count));
  } else {
    blob.push_back(static_cast<uint8_t>(128 + count % 128));
    blob.push_back(static_cast<uint8_t>(count / 128));
  }
  blob.insert(blob.end(), token.begin(), token.end());
}
}  // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  FuzzedDataProvider provider(data, size);
  const uint8_t cut = provider.ConsumeIntegral<uint8_t>();
  std::vector<uint8_t> blob;
  while (provider.remaining_bytes() > 0) {
    const size_t count =
        provider.ConsumeIntegralInRange<size_t>(0, kMaxTokenSize);
    append_token(blob, provider.ConsumeBytes<uint8_t>(count));
  }
  if (cut < kTruncationLimit) {
    blob.resize(blob.size() - std::min<size_t>(cut, blob.size()));
  }

  // An exact-size copy: the builder's spare capacity would hide reads past the end of the blob.
  const std::vector<uint8_t> exact(blob.begin(), blob.end());
  try {
    BinTokenizer tokenizer(exact.data(), exact.size());

    const size_t text_size = std::min(exact.size(), kMaxTextSize);
    const std::string text(exact.begin(), exact.begin() + text_size);
    try {
      const std::vector<int32_t> tokens =
          tokenizer.text_to_tokens<int32_t>(text);
      tokenizer.tokens_to_text<int32_t>(tokens);
    } catch (const std::exception &) {
      // Unknown byte sequences legitimately throw.
    }
  } catch (const std::exception &) {
    // Malformed blobs legitimately throw.
  }
  return 0;
}
