// Test hash_create and then call hash_get_num_entries from PostgreSQL
#include "postgres.h"
#include "fmgr.h"
#include "utils/hsearch.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(test_hash_v2);

Datum
test_hash_v2(PG_FUNCTION_ARGS)
{
    HASHCTL ctl;
    HTAB *hashtab;
    long count;
    
    elog(NOTICE, "test_hash_v2: creating hash table");
    
    memset(&ctl, 0, sizeof(ctl));
    ctl.keysize = sizeof(uint32);
    ctl.entrysize = sizeof(uint32) * 2;
    
    hashtab = hash_create("test_v2", 2, &ctl, HASH_ELEM | HASH_BLOBS);
    
    if (hashtab == NULL)
    {
        elog(ERROR, "hash_create returned NULL");
    }
    
    elog(NOTICE, "test_hash_v2: hashtab = %p (0x%llx)", 
         (void*)hashtab, (unsigned long long)(intptr_t)hashtab);
    
    // This call goes into PostgreSQL's dynahash.c code
    elog(NOTICE, "test_hash_v2: calling hash_get_num_entries");
    count = hash_get_num_entries(hashtab);
    elog(NOTICE, "test_hash_v2: count = %ld", count);
    
    // Clean up
    elog(NOTICE, "test_hash_v2: calling hash_destroy");
    hash_destroy(hashtab);
    
    elog(NOTICE, "test_hash_v2: done!");
    
    PG_RETURN_INT32(0);
}
