/*
 * Test extension using two-level namespace to bind to PostgreSQL's symbols
 * instead of allowing flat namespace symbol resolution which picks up libc's
 * hash_create on macOS.
 *
 * Compile with:
 *   clang -dynamiclib -twolevel_namespace \
 *     -I$(pg_config --includedir-server) \
 *     -L$(pg_config --libdir) -lpq \
 *     -o test_twolevel.dylib test_twolevel.c
 *
 * Or linking directly against postgres:
 *   clang -dynamiclib -twolevel_namespace \
 *     -I$(pg_config --includedir-server) \
 *     $(pg_config --bindir)/postgres \
 *     -o test_twolevel.dylib test_twolevel.c
 */

#include "postgres.h"
#include "fmgr.h"
#include "utils/hsearch.h"
#include "utils/memutils.h"

PG_MODULE_MAGIC;
PG_FUNCTION_INFO_V1(test_twolevel);

Datum test_twolevel(PG_FUNCTION_ARGS)
{
    HASHCTL hashctl;
    HTAB *htab;
    
    elog(NOTICE, "test_twolevel: Starting hash table test");
    elog(NOTICE, "  hash_create address: %p", (void *)hash_create);
    elog(NOTICE, "  hash_destroy address: %p", (void *)hash_destroy);
    
    memset(&hashctl, 0, sizeof(hashctl));
    hashctl.keysize = sizeof(int);
    hashctl.entrysize = sizeof(int) * 2;
    hashctl.hcxt = CurrentMemoryContext;
    
    elog(NOTICE, "  Calling hash_create...");
    htab = hash_create("test_twolevel_table", 16, &hashctl,
                       HASH_ELEM | HASH_BLOBS | HASH_CONTEXT);
    
    if (htab == NULL) {
        elog(ERROR, "hash_create returned NULL");
    }
    
    elog(NOTICE, "  hash_create returned: %p", (void *)htab);
    
    long num_entries = hash_get_num_entries(htab);
    elog(NOTICE, "  hash_get_num_entries: %ld", num_entries);
    
    elog(NOTICE, "  Calling hash_destroy...");
    hash_destroy(htab);
    
    elog(NOTICE, "test_twolevel: SUCCESS!");
    
    PG_RETURN_INT32(0);
}
