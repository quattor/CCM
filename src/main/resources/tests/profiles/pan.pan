object template pan;

"/data/a" = 1;
"/data/b" = list(true, false);
"/data/c/x" = "OK";

# For the tests
variable DATA = value("/");
"/metaconfig/contents" = DATA;
"/metaconfig/module" = "pan";
