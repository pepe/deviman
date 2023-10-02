(declare-project
  :name "deviman"
  :description ```Web application for managing devices. ```
  :version "0.0.1"
  :dependencies ["spork" "jhydro"])

(declare-executable
  :name "deviman"
  :entry "deviman/init.janet")
