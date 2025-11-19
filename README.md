# dev
This is a repository for development tools and scripts. Ideally, I would like to be up and running on any
machine in a matter of minutes.

### Setup
1. run `make`
1. run `make ensure-oh-my-zsh` if desired

### Some notes
1. I have a seperate repo for my neovim config which is references as a submodule here.
1. All of the dotfiles on the target installation machine are simply symlinks to the files in this repo. 
Change a setting in this repo? It will update on your system.
