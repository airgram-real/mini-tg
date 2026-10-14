// TDJson C API (new client-id interface) — provided by TDLibFramework
#ifndef TD_BRIDGE_H
#define TD_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

int32_t td_create_client_id(void);
void td_send(int32_t client_id, const char *request);
const char *td_receive(double timeout);
const char *td_execute(const char *request);

#ifdef __cplusplus
}
#endif

#endif /* TD_BRIDGE_H */
