
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
> jpm -l deps
```

To test the codebase run: 

```
> jpm -l test
```

To run the development server, run:

```
> jpm -l janet deviman/init.janet
```

To watch the project files for modification, and run the development server, which restarts when any file is modified, run:

```
jpm -l janet bin/dev.janet
```