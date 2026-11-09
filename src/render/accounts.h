#ifndef ACCOUNTS_H
#define ACCOUNTS_H

#ifdef __cplusplus
extern "C" {
#endif

void accounts_init(void);
int accounts_get_count(void);
const char* accounts_get_name(int index);
const char* accounts_get_uuid(int index);
int accounts_get_selected(void);
void accounts_set_selected(int index);
int accounts_create(const char* name);
int accounts_delete(int index);
int accounts_save(void);

#ifdef __cplusplus
}
#endif

#endif
