#include "postgres.h"
#include "fmgr.h"
#include "utils/hsearch.h"
#include "utils/memutils.h"
#include "utils/elog.h"

PG_MODULE_MAGIC;

typedef struct
{
    uint32 key;
    uint32 value;
} IntEntry;

PG_FUNCTION_INFO_V1(test_hsearch_c_run);

Datum
test_hsearch_c_run(PG_FUNCTION_ARGS)
{
    HASHCTL ctl;
    HTAB *hashtab;
    long num_entries;

    elog(NOTICE, "Running test_hsearch_c_run - FULL TEST");
    elog(NOTICE, "sizeof(HASHCTL) = %zu", sizeof(HASHCTL));

    memset(&ctl, 0, sizeof(ctl));
    ctl.keysize = sizeof(uint32);
    ctl.entrysize = sizeof(IntEntry);

    elog(NOTICE, "Calling hash_create...");
    
    // Test: call a known function and print its address
    extern void *MemoryContextAlloc(void *context, Size size);
    elog(NOTICE, "Address of MemoryContextAlloc: %p", (void*)MemoryContextAlloc);
    
    // Call hash_create and print all 8 bytes of the return value
    elog(NOTICE, "Address of hash_create: %p", (void*)hash_create);
    
    hashtab = hash_create("test_hsearch C table",
                          2,
                          &ctl,
                          HASH_ELEM | HASH_BLOBS);

    if (hashtab == NULL)
    {
        elog(ERROR, "Failed to create hash table");
    }

    // Print the raw pointer value multiple ways
    elog(NOTICE, "hash_create returned:");
    elog(NOTICE, "  as %%p:   %p", (void*)hashtab);
    elog(NOTICE, "  as %%lx:  0x%lx", (unsigned long)hashtab);
    elog(NOTICE, "  as %%llx: 0x%llx", (unsigned long long)hashtab);
    
    // Debug: dump first 128 bytes of HTAB struct
    elog(NOTICE, "Dumping HTAB memory (first 128 bytes):");
    unsigned char *p = (unsigned char *)hashtab;
    for (int i = 0; i < 128; i += 16) {
        elog(NOTICE, "  +%03d: %02x %02x %02x %02x  %02x %02x %02x %02x  %02x %02x %02x %02x  %02x %02x %02x %02x",
             i,
             p[i+0], p[i+1], p[i+2], p[i+3],
             p[i+4], p[i+5], p[i+6], p[i+7],
             p[i+8], p[i+9], p[i+10], p[i+11],
             p[i+12], p[i+13], p[i+14], p[i+15]);
    }
    
    // Read pointers as 64-bit values at various offsets
    uint64 *u64 = (uint64 *)hashtab;
    elog(NOTICE, "As uint64 pointers:");
    elog(NOTICE, "  offset 0 (hctl):    0x%016llx", (unsigned long long)u64[0]);
    elog(NOTICE, "  offset 8 (dir):     0x%016llx", (unsigned long long)u64[1]);
    elog(NOTICE, "  offset 16 (hash):   0x%016llx", (unsigned long long)u64[2]);
    elog(NOTICE, "  offset 24 (match):  0x%016llx", (unsigned long long)u64[3]);
    elog(NOTICE, "  offset 32 (keycopy):0x%016llx", (unsigned long long)u64[4]);
    elog(NOTICE, "  offset 40 (alloc):  0x%016llx", (unsigned long long)u64[5]);
    elog(NOTICE, "  offset 48 (hcxt):   0x%016llx", (unsigned long long)u64[6]);
    elog(NOTICE, "  offset 56 (tabname):0x%016llx", (unsigned long long)u64[7]);
    
    // Check if hctl looks like a valid pointer
    void *hctl = (void*)u64[0];
    elog(NOTICE, "Trying to read from hctl %p...", hctl);
    if (hctl != NULL && (uint64)hctl > 0x1000) {
        unsigned char first = *((unsigned char*)hctl);
        elog(NOTICE, "First byte at hctl: 0x%02x", first);
    } else {
        elog(NOTICE, "hctl looks invalid, skipping dereference");
    }

    elog(NOTICE, "Calling hash_get_num_entries...");
    num_entries = hash_get_num_entries(hashtab);
    elog(NOTICE, "hash_get_num_entries returned: %ld", num_entries);

    if (num_entries != 0)
    {
        elog(ERROR, "Expected 0 entries, got %ld", num_entries);
    }

    elog(NOTICE, "Calling hash_destroy...");
    hash_destroy(hashtab);

    elog(NOTICE, "test_hsearch_c_run finished successfully!");

    PG_RETURN_INT32(0);
}
