object template tabcompletion_safe_unescape;

prefix "/software/components";
"metaconfig/services/{/my/test/file}/contents/data" = 1;
"metaconfig/services/{/my/test2/file2}/contents/data" = 2;

# add some more components to test the components tabcompletion function
# this part has nothing to do with safe unescape
"mycomponent/active" = true;
"inactive/active" = false;
