name "zenoss-server"
description "Zenoss Server Role"
run_list(
         "recipe[zenoss::api]",
         "recipe[zenoss::monitor]"
)
default_attributes()
override_attributes()

