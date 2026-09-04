# Build without SwiftPM: one swiftc invocation, no package resolution, no network.
SWIFTC ?= swiftc
BIN    ?= bin/origami

$(BIN): $(wildcard Sources/*.swift)
	@mkdir -p bin
	$(SWIFTC) -O Sources/*.swift -o $(BIN)

.PHONY: check clean
# Build, then run the bundled four-flap example, which must produce a verified
# crease pattern.  Use this to confirm a fresh checkout works.
check: $(BIN)
	@rm -rf /tmp/origami-check
	@./$(BIN) examples/star4/src -o /tmp/origami-check --granularity module --uniform --restarts 40 -q
	@grep -q "Verified crease pattern emitted" /tmp/origami-check/report.md \
		&& echo "OK: verified crease pattern emitted for examples/star4" \
		|| (echo "FAIL: see /tmp/origami-check/report.md"; exit 1)

clean:
	rm -rf bin .build
