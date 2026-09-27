/*
 * Link stubs for Perry's `perry-ext-http` archive.
 *
 * Upstream ships perry-ext-http as a separate `libperry_ext_http.a` staged
 * next to the compiler. The npm musl package this build is based on does not
 * include it, and upstream stopped publishing musl packages after 0.5.1220,
 * so the archive cannot be obtained for this target.
 *
 * Without it, ANY program that pulls Perry's full stdlib fails to link —
 * not just ones that use HTTP. Importing node:crypto, node:events or
 * node:zlib pulls the same stdlib codegen units, which reference these
 * fourteen `js_ext_http_*` / `js_http_*` symbols, so the link dies on an
 * undefined `js_ext_http_agent_is_handle` no matter what the program does.
 *
 * Every stub returns 0. Interpreted through Perry's conventions that is
 * `false` for the `is_*` / `has_*` predicates, `NULL` for the handle
 * accessors, and +0 for the dispatch entry points — all falsy, so the
 * event loop's "is there pending HTTP work?" probe answers no and control
 * flow stays on the paths a non-networking program takes.
 *
 * These must NOT abort: `js_http_has_pending` is consulted by the event loop
 * of every program linked against the full stdlib.
 *
 * Consequence: a program that genuinely uses node:http/https/net/tls/ws or
 * fetch() links and runs, but its network objects behave as empty. That is
 * a softer failure than the link error it replaces, not a working network
 * stack.
 *
 * Signatures are deliberately uniform `unsigned long long f(void)`. These
 * are extern "C" symbols resolved by name; on aarch64 unused arguments are
 * ignored, and the all-zero return is meaningful for every caller.
 */

typedef unsigned long long u64;

u64 js_ext_http_agent_dispatch_method(void) { return 0; }
u64 js_ext_http_agent_dispatch_property(void) { return 0; }
u64 js_ext_http_agent_dispatch_property_set(void) { return 0; }
u64 js_ext_http_agent_is_handle(void) { return 0; }
u64 js_ext_http_client_incoming_message_is_handle(void) { return 0; }
u64 js_ext_http_client_incoming_message_set_encoding(void) { return 0; }
u64 js_ext_http_client_inflight(void) { return 0; }
u64 js_ext_http_client_request_dispatch_method(void) { return 0; }
u64 js_ext_http_client_request_dispatch_property(void) { return 0; }
u64 js_ext_http_client_request_is_handle(void) { return 0; }
u64 js_http_has_pending(void) { return 0; }
u64 js_http_incoming_message_pipe(void) { return 0; }
u64 js_http_is_incoming_message(void) { return 0; }
u64 js_http_response_trailers(void) { return 0; }
