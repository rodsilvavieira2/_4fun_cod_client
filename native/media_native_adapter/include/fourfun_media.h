// Proposta ABI v1 de controle (§22.4 do plano). Não transporta PCM por
// JSON. FRB e ABI C chamam o mesmo control actor no Rust.
#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint64_t FourfunEngineId;
typedef uint32_t FourfunStatus; /* 0=OK, demais valores estáveis */

typedef struct {
  uint32_t struct_size;
  uint32_t abi_version;
  uint64_t incarnation;
  uint32_t flags;
} FourfunCreateOptions;

typedef struct {
  uint8_t* data;
  size_t len;
} FourfunOwnedBuffer;

/* Status: 0=OK, 1=InvalidArgs, 2=AbiMismatch, 3=InvalidHandle, 4=Busy,
 * 5=NoEvent (poll sem evento — distinto de erro), 6=Unauthorized,
 * 7=Internal. Espelha AbiStatus do media_core. */
uint32_t fourfun_media_abi_version(void);
FourfunStatus fourfun_media_create(
    const FourfunCreateOptions* options, FourfunEngineId* out_id);
FourfunStatus fourfun_media_submit_json(
    FourfunEngineId id, const uint8_t* utf8, size_t len, uint64_t* out_ticket);
FourfunStatus fourfun_media_snapshot_json(
    FourfunEngineId id, FourfunOwnedBuffer* out_snapshot);
FourfunStatus fourfun_media_poll_event(
    FourfunEngineId id, FourfunOwnedBuffer* out_event);
FourfunStatus fourfun_media_close_tx(FourfunEngineId id);
FourfunStatus fourfun_media_dispose(FourfunEngineId id);
void fourfun_media_buffer_free(FourfunOwnedBuffer* buffer);

#ifdef __cplusplus
}  // extern "C"
#endif
