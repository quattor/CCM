object template pan;

"/data/one" = 1;
"/data/oneandahalf" = 1.5;
"/data/listtruefalse" = list(true, false);
"/data/hash/x" = "OK";

"/special/not_escaped_d" = "not_escaped_d";
"/special/{escaped data}" = "escaped data";

# Some larger, deeper example
"/z/deep/a" = "a";
"/z/deep/list/0/a/b" = "a";
"/z/deep/list/1" = dict(
    "atest", 1,
    "btest", 1.5,
    "ctest", true,
    "dtest", false,
    "etest", "ok",
);
"/z/deep/list/2/fake" = 1;

