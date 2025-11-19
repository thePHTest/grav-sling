package main

import "core:fmt"

bar :: #type proc(x: int) -> int

bar_impl: bar : proc(x: int) -> int {
    return x
}

foo :: proc(callback: bar) -> int {
    return callback(20)
}

main :: proc() {
	arr : [?]int = [?]int{1, 2, 3, 4}
	fmt.println(arr)
    foo(bar_impl)
}
