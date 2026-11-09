#ifndef IRIS_SHADER_H
#define IRIS_SHADER_H

#ifdef __cplusplus
extern "C" {
#endif

#define MAX_SHADER_PACKS 32
#define MAX_SHADER_NAME 128
#define MAX_SHADER_PATH 512

typedef struct {
    char name[MAX_SHADER_NAME];
    char path[MAX_SHADER_PATH];
    int is_internal;
} IrisShaderPack;

void iris_shader_discover(void);
int iris_shader_get_count(void);
const char* iris_shader_get_name(int index);
const char* iris_shader_get_path(int index);
int iris_shader_get_selected(void);
void iris_shader_set_selected(int index);
int iris_shader_is_active(void);

#ifdef __cplusplus
}
#endif

#endif
