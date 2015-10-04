object template general;

"/name_level0" = "value_level0";
"/nameb_level0" = "valueb_level0";
"/list_level0" = list(
    "l0_value_el0",
    "l0_value_el1",
    );
"/list_level0b/l0_dict_el2" = list(
    dict(
        "ll0_name1", "ll0_value1",
        "ll0_list", list("ll0_el0", "ll0_el1"),
    ),
);

prefix "/dict_level0";
"name_level1" = "value_level1";
"list_level1" = list(
    "l1_value_el0",
    "l1_value_el1",
    );
"list_level1b/l1_dict_el2" = list(
     dict(
        "ll1_name1", "ll1_value1",
        "ll1_list", list("ll1_el0", "ll1_el1"),
    ),
);

prefix "/dict_level0/list_level1b/level2";
"name_level2" = "value_level2";
"list_level2" = list(
    "l2_value_el0",
    "l2_value_el1",
    );
"list_level2b/l2_dict_el2" = list(
     dict(
        "ll2_name1", "ll2_value1",
        "ll2_list", list("ll2_el0", "ll2_el1"),
    ),
);
