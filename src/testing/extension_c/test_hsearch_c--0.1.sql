-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION test_hsearch_c" to load this file. \quit

CREATE FUNCTION test_hsearch_c_run()
RETURNS integer
AS '$libdir/test_hsearch_c'
LANGUAGE C;
