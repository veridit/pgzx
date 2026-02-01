#include "postgres.h"
#include "fmgr.h"
#include "utils/hsearch.h"

PG_MODULE_MAGIC;
PG_FUNCTION_INFO_V1(test_func_addr);

// Declare hash_create to get its address
extern HTAB *hash_create(const char *tabname, long nelem, const HASHCTL *info, int flags);

Datum test_func_addr(PG_FUNCTION_ARGS)
{
    void *hash_create_addr = (void *)hash_create;
    void *hash_get_num_entries_addr = (void *)hash_get_num_entries;
    void *hash_destroy_addr = (void *)hash_destroy;
    
    elog(NOTICE, "Function addresses as seen by extension:");
    elog(NOTICE, "  hash_create:          %p", hash_create_addr);
    elog(NOTICE, "  hash_get_num_entries: %p", hash_get_num_entries_addr);
    elog(NOTICE, "  hash_destroy:         %p", hash_destroy_addr);
    
    // Expected addresses from nm (arm64 slice):
    // _hash_create:          0x00000001003f6b7c
    // _hash_get_num_entries: 0x00000001003f7b58
    // _hash_destroy:         0x00000001003f7384
    
    PG_RETURN_INT32(0);
}
