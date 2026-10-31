/* Fuzz the Ring object file (.ringo) reader: header checks, section parsing,
 * string decoding and the byte-code list builder. The loaded program is never run (lRun = 0). */
#include "ring.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
	char *buf;
	int ok;
	RingState *state;
	/* Same precondition as ring_objfile_processfile(), the real caller: a minimum size and the
	** end-of-file trailer. The section parser itself does no bounds checking. */
	if (size < RING_OBJFILE_MINSIZE || memcmp(data + size - 6, "\n$!${$", 6) != 0) {
		return -1;
	}
	buf = (char *)malloc(size + 1);
	if (buf == NULL) {
		return -1;
	}
	memcpy(buf, data, size);
	buf[size] = '\0';
	state = ring_state_new();
	state->lRun = 0;
	ring_state_runobjectstring(state, buf, (unsigned int)size, "fuzz.ringo");
	ok = state->lRunFromObjectFile;
	ring_state_delete(state);
	free(buf);
	return ok ? 0 : -1;
}
