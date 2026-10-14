// TDJson C API declarations (linked against libtdjson from TDLib)
#ifndef TD_BRIDGE_H
#define TD_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

void *td_json_client_create(void);
void  td_json_client_send(void *client, const char *request);
const char *td_json_client_receive(void *client, double timeout);
const char *td_json_client_execute(void *client, const char *request);
void  td_json_client_destroy(void *client);

#ifdef __cplusplus
}
#endif

#endif /* TD_BRIDGE_H */
