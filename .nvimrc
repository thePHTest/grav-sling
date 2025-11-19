:set makeprg=build.bat"
nmap <F1> :wa <bar> :make<Enter>
nmap <F2> :!project.bat<Enter>
nmap <F3> :wa <bar> :make 1<Enter>
nmap <F4> :!project.bat 1<Enter>
:next **/*
:b src/project.odin
