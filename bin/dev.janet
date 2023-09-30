(import spork/path)
(import spork/sh)
(import spork/misc)

(defn all-project-files
  ```
  Returns all code files in the project as array of strings, 
  or if `modified` is truthy as table where filenames are keys
  and their last modification time as value.
  ```
  [&opt modified]
  (def list
    (filter
      |(peg/match '(to (* "janet" -1)) $)
      (array/concat (sh/list-all-files "./")
                    ["project.janet"])))
  (if modified
    (tabseq [[i f] :pairs list] f (os/stat f :modified))
    list))

(defn watch
  "Spawns commands, watch all project files and respawns on changes."
  [& cmds]
  (var ift (all-project-files true))
  (var s (os/spawn cmds :p))
  (var restart false)
  (forever
    (def cft (all-project-files true))
    (eachk f cft
      (unless (= (ift f) (cft f))
        (print "\nFile " f " modified")
        (set restart true))
      (unless (ift f)
        (print "\nFile " f " created")
        (set restart true))
      (when restart
        (os/proc-kill s)
        (print "Restarting")
        (set s (os/spawn cmds :p))
        (set ift (all-project-files true))
        (set restart false)))
    (ev/sleep 1)))

(def jpm
  "On windows you have to add .bar"
  (misc/cond-> "jpm" (= (os/which) :windows) (string ".bat")))

(watch jpm "-l" "janet" (path/join "deviman" "init.janet"))
