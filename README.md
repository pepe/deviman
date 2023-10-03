
# deviman

Example application in Janet programming language for discorvery and 
administration of simple network devices (arduinos, etc).

## Features

- Web application
- Only standart library and spork.
- No database, just pure Janet datastructures marshalled to file.
- Extensive use of `ev`.
- On frontend use htmx, missing and hyperscript.

## Development

To download development dependencies, I mean `spork`, run:

```
jpm -l deps
```

To test the codebase run: 

```
jpm -l test
```

To create initial store, run:

```
jpm -l janet bin/store.janet
```

To run the development server, run:

```
jpm -l janet deviman/init.janet store.jimage
```

On the address `http://localhost:8000/` in the browser you should see the application.

To watch the project files for modification, and run the development server, which restarts when any file is modified, run:

```
jpm -l janet bin/dev.janet
```

To simulate device connection to the manager, run:

```
jpm -l janet bin/connect.janet [num]
```

Where `num` is optional number of generated connections.
