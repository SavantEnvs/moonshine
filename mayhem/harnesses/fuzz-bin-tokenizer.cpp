// libFuzzer harness for the binary tokenizer.
//
// The in-memory BinTokenizer constructor parses an untrusted byte blob (a tokenizer.bin loaded from
// disk or an app bundle, or handed to the model loaders from memory). The input is that blob followed
// by one control byte: the number of leading blob bytes (capped at 128) that are then reused as text
// for a text_to_tokens / tokens_to_text round trip. Exceptions are the library's documented failure
// mode, so they are caught and ignored; only sanitizer errors (out-of-bounds reads, UB) fail the run.
//
// The control byte keeps libFuzzer's built-in default seed ("\n") from being a blob by itself: that
// seed would otherwise be the first input the harness sees and ends every run before it starts.

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <exception>
#include <string>
#include <vector>

#include "bin-tokenizer.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  if (size == 0) {
    return 0;
  }
  const size_t blob_size = size - 1;
  const size_t text_size = std::min<size_t>({blob_size, data[blob_size], 128});
  try {
    BinTokenizer tokenizer(data, blob_size);

    const std::string text(data, data + text_size);
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
