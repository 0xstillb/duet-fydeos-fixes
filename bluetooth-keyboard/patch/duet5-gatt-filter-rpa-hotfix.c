#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static const char kOpenSymbol[] = "_Z14BTA_GATTC_OpenhRK10RawAddressh18tBTM_BLE_CONN_TYPE13tBT_TRANSPORTbhtbE3$_0";
typedef void (*open9_fn)(uint8_t, const void *, uint8_t, uint8_t, uint8_t, bool, uint8_t, uint16_t, bool);
static open9_fn real_open9;

static bool is_legacy_duet_identity_address(const uint8_t *a) {
  return a != NULL && a[0] == 0xcc && a[1] == 0x59 && a[2] == 0x35 && a[3] == 0x9f;
}

/* Duet uses a resolvable private address; BTA_GATTC_Open sees the RPA rather
 * than the bonded identity address. These native client IDs are the Floss
 * HoGP/BAS clients observed on this exact FydeOS image. */
static bool is_known_native_duet_client(uint8_t client_if) {
  return client_if == 43 || client_if == 45 || client_if == 46 ||
         client_if == 48 || client_if == 50;
}

static int bridge_client_id(void) {
  char buf[32] = {0};
  int fd = open("/tmp/duet5-bridge-client-id", O_RDONLY | O_CLOEXEC);
  if (fd < 0) return -1;
  ssize_t n = read(fd, buf, sizeof(buf) - 1);
  close(fd);
  if (n <= 0) return -1;
  return (int)strtol(buf, NULL, 10);
}

static void filter_log(uint8_t client_if, uint8_t conn_type, const uint8_t *a, bool blocked) {
  int fd = open("/tmp/duet5-gatt-filter.log", O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0600);
  if (fd < 0) return;
  char line[160];
  int n = snprintf(line, sizeof(line), "client=%u type=%u addr=%02x:%02x:%02x:%02x:%02x:%02x %s\\n",
                   client_if, conn_type, a[0], a[1], a[2], a[3], a[4], a[5],
                   blocked ? "BLOCK" : "ALLOW");
  (void)write(fd, line, (size_t)n);
  close(fd);
}

void duet5_open9(uint8_t client_if, const void *remote_bda, uint8_t addr_type,
                 uint8_t conn_type, uint8_t transport, bool opportunistic,
                 uint8_t initiating_phys, uint16_t preferred_mtu, bool prefer_relax_mode)
    __asm__("_Z14BTA_GATTC_OpenhRK10RawAddressh18tBTM_BLE_CONN_TYPE13tBT_TRANSPORTbhtbE3$_0");

void duet5_open9(uint8_t client_if, const void *remote_bda, uint8_t addr_type,
                 uint8_t conn_type, uint8_t transport, bool opportunistic,
                 uint8_t initiating_phys, uint16_t preferred_mtu, bool prefer_relax_mode) {
  if (real_open9 == NULL) {
    void *sym = dlsym(RTLD_NEXT, kOpenSymbol);
    memcpy(&real_open9, &sym, sizeof(real_open9));
  }
  const uint8_t *a = (const uint8_t *)remote_bda;
  int allowed = bridge_client_id();
  bool block = allowed >= 0 && client_if != (uint8_t)allowed &&
               is_known_native_duet_client(client_if);
  if (is_legacy_duet_identity_address(a) &&
      (allowed < 0 || client_if != (uint8_t)allowed)) {
    block = true;
  }
  if (block) {
    filter_log(client_if, conn_type, a, true);
    return;
  }
  if (is_legacy_duet_identity_address(a)) {
    filter_log(client_if, conn_type, a, false);
  }
  if (real_open9 != NULL) {
    real_open9(client_if, remote_bda, addr_type, conn_type, transport, opportunistic,
               initiating_phys, preferred_mtu, prefer_relax_mode);
  }
}
