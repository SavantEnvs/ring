/* Fuzz Ring's scanner, parser and code generator on source text. The program is
 * compiled only (lRun = 0), never executed, so guest code cannot reach the host. */
#include "ring.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
	char *src;
	int ok;
	RingState *state;
	src = (char *)malloc(size + 1);
	if (src == NULL) {
		return -1;
	}
	memcpy(src, data, size);
	src[size] = '\0';
	state = ring_state_new();
	state->lRun = 0;
	ok = ring_state_runstring(state, src);
	ring_state_delete(state);
	free(src);
	return ok ? 0 : -1;
}
