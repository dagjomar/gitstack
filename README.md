# Git Stack
## A lightweight command-line tool for effortless Git branch stack management.

[![Tests](https://github.com/dagjomar/gitstack/actions/workflows/test.yml/badge.svg)](https://github.com/dagjomar/gitstack/actions/workflows/test.yml)

<img src="./docs/gitstack.jpeg" alt="Git Stack Illustration" width="500"/>

<br />

## Overview

Git Stack is a simple, no-frills command-line utility that makes managing stacked Git branches quick and painless. Whether you're creating, incrementing, or cleaning up branches, Git Stack helps you stay organized with minimal effort, so you can focus on what matters—writing code.

## Features

- **Create Stacked Branches:** Easily initialize a new branch stack with a base name.

- **Increment Branches:** Quickly create subsequent branches in the stack with an incremented suffix.

- **Delete Branch Stacks:** Force-delete entire stacks of branches efficiently.

## Installation

1. **Clone the Repository:**

   ```bash
   git clone https://github.com/yourusername/gitstack.git
   cd gitstack
   ```

2. **Make the Script Executable:**

```bash
  chmod +x bin/gitstack.sh
```

3. **Make the Script Executable:**
   To simplify usage, set up a Git alias to run the script with git stack:

```bash
  git config --global alias.stack '!bash /path/to/gitstack/bin/gitstack.sh'
```

Replace /path/to/gitstack/bin/gitstack.sh with the absolute path to gitstack.sh on your system. This alias allows you to execute the script using git stack.

## Usage

After setting up the alias, you can use the following commands:

- **Create a New Branch Stack:**

```bash
  git stack create <base_name>
```

Initializes a new branch named <base_name>-0.

- **Increment the Current Branch:**

```bash
  git stack increment
```

Creates a new branch by incrementing the current branch's suffix.

- **Delete a Branch Stack:**

```bash
  git stack delete -f <base_name>
```

Force-deletes all local branches matching <base_name>-\*.

Alternatively, to interactively delete the current branch's stack:

```bash
  git stack delete
```

This command prompts for confirmation before deleting the stack.

## TODOs
- Create better usage examples and use cases explaining how to best us it in a normal workflow
- Create command to manage rebasing

## Contributing

Contributions are welcome! Feel free to submit issues or pull requests to enhance Git Stack.
