#include "accounts.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MAX_ACCOUNTS 64
#define MAX_NAME_LEN 64
#define MAX_UUID_LEN 40
#define ACCOUNTS_FILE "accounts.json"

typedef struct {
    char name[MAX_NAME_LEN];
    char uuid[MAX_UUID_LEN];
} Account;

static Account s_accounts[MAX_ACCOUNTS];
static int s_account_count = 0;
static int s_selected_account = 0;

/* Generates a deterministic formatted UUID for offline accounts */
static void generate_offline_uuid(const char* name, char* out_uuid) {
    unsigned int hash = 5381;
    size_t len = strlen(name);
    for (size_t i = 0; i < len; i++) {
        hash = ((hash << 5) + hash) + (unsigned char)name[i];
    }
    snprintf(out_uuid, MAX_UUID_LEN, "%08x-%04x-4%03x-%04x-%012llx",
             hash, (hash >> 16) & 0xFFFF, hash & 0x0FFF,
             0x8000 | ((hash >> 8) & 0x3FFF),
             (unsigned long long)hash * 6364136223846793005ULL);
}

int accounts_save(void) {
    FILE* f = fopen(ACCOUNTS_FILE, "w");
    if (!f) return 0;
    fprintf(f, "{\n");
    fprintf(f, "  \"selected\": %d,\n", s_selected_account);
    fprintf(f, "  \"accounts\": [\n");
    for (int i = 0; i < s_account_count; i++) {
        fprintf(f, "    {\"name\": \"%s\", \"uuid\": \"%s\"}%s\n",
                s_accounts[i].name, s_accounts[i].uuid,
                (i + 1 < s_account_count) ? "," : "");
    }
    fprintf(f, "  ]\n");
    fprintf(f, "}\n");
    fclose(f);
    return 1;
}

void accounts_init(void) {
    s_account_count = 0;
    s_selected_account = 0;

    FILE* f = fopen(ACCOUNTS_FILE, "r");
    if (f) {
        char line[512];
        while (fgets(line, sizeof(line), f)) {
            char* p_sel = strstr(line, "\"selected\":");
            if (p_sel) {
                s_selected_account = atoi(p_sel + 11);
            }
            char* p_name = strstr(line, "\"name\":");
            char* p_uuid = strstr(line, "\"uuid\":");
            if (p_name && p_uuid && s_account_count < MAX_ACCOUNTS) {
                char name[MAX_NAME_LEN] = {0};
                char uuid[MAX_UUID_LEN] = {0};
                if (sscanf(p_name, "\"name\": \"%63[^\"]\"", name) == 1 &&
                    sscanf(p_uuid, "\"uuid\": \"%39[^\"]\"", uuid) == 1) {
                    strncpy(s_accounts[s_account_count].name, name, MAX_NAME_LEN - 1);
                    strncpy(s_accounts[s_account_count].uuid, uuid, MAX_UUID_LEN - 1);
                    s_account_count++;
                }
            }
        }
        fclose(f);
    }

    if (s_account_count == 0) {
        // Defaults
        strncpy(s_accounts[0].name, "Steve", MAX_NAME_LEN - 1);
        generate_offline_uuid("Steve", s_accounts[0].uuid);
        strncpy(s_accounts[1].name, "Alex", MAX_NAME_LEN - 1);
        generate_offline_uuid("Alex", s_accounts[1].uuid);
        s_account_count = 2;
        s_selected_account = 0;
        accounts_save();
    }

    if (s_selected_account < 0 || s_selected_account >= s_account_count) {
        s_selected_account = 0;
    }
}

int accounts_get_count(void) {
    return s_account_count;
}

const char* accounts_get_name(int index) {
    if (index >= 0 && index < s_account_count) {
        return s_accounts[index].name;
    }
    return "";
}

const char* accounts_get_uuid(int index) {
    if (index >= 0 && index < s_account_count) {
        return s_accounts[index].uuid;
    }
    return "";
}

int accounts_get_selected(void) {
    return s_selected_account;
}

void accounts_set_selected(int index) {
    if (index >= 0 && index < s_account_count) {
        s_selected_account = index;
        accounts_save();
    }
}

int accounts_create(const char* name) {
    if (!name || strlen(name) == 0 || s_account_count >= MAX_ACCOUNTS) {
        return 0;
    }
    for (int i = 0; i < s_account_count; i++) {
        if (strcmp(s_accounts[i].name, name) == 0) {
            s_selected_account = i;
            accounts_save();
            return 1;
        }
    }
    strncpy(s_accounts[s_account_count].name, name, MAX_NAME_LEN - 1);
    generate_offline_uuid(name, s_accounts[s_account_count].uuid);
    s_selected_account = s_account_count;
    s_account_count++;
    accounts_save();
    return 1;
}

int accounts_delete(int index) {
    if (s_account_count <= 1 || index < 0 || index >= s_account_count) {
        return 0;
    }
    for (int i = index; i < s_account_count - 1; i++) {
        s_accounts[i] = s_accounts[i + 1];
    }
    s_account_count--;
    if (s_selected_account >= s_account_count) {
        s_selected_account = s_account_count - 1;
    }
    accounts_save();
    return 1;
}
