package gen

import "core:reflect"
import "core:odin/parser"
import "core:os"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:log"
import "core:strings"

main :: proc() {
	context.logger = log.create_console_logger()
	filepath := "../deps/odin-imgui/imgui.odin"
	p := parser.default_parser()
	bytes, file_ok := os.read_entire_file(filepath)
	if file_ok {

		source := string(bytes)

		pkg := ast.Package {
			kind = .Normal,
		}

		file := ast.File {
			pkg      = &pkg,
			src      = source,
			fullpath = filepath,
		}

		parse_ok := parser.parse_file(&p, &file)

		builder := strings.builder_make()

		Proc_Visitor_Data :: struct {
			builder : ^strings.Builder,
		}
		proc_visitor_data := Proc_Visitor_Data{
			builder = &builder
		}

		proc_visitor := ast.Visitor {
			visit = proc(visitor : ^ast.Visitor, node : ^ast.Node) -> ^ast.Visitor {
				data := cast(^Proc_Visitor_Data)visitor.data
				#partial switch derived in node.derived {
				case ^ast.Ident:
				strings.write_string(data.builder, derived.name)
				case ^ast.Proc_Type:
				}

				return visitor
			},
			data = &proc_visitor_data
		}

		Root_Visitor_Data :: struct {
			proc_visitor : ^ast.Visitor,
		}

		root_visitor_data := Root_Visitor_Data{
			&proc_visitor,
		}

		visitor := ast.Visitor{
			visit = proc(visitor : ^ast.Visitor, node : ^ast.Node) -> ^ast.Visitor {
				data := cast(^Root_Visitor_Data)visitor.data
				if node != nil {
					if ident, ok := node.derived.(^ast.Ident); ok {
						//data.last_ident_node = node
					}
					if proc_type, ok := node.derived.(^ast.Proc_Type); ok {
						ast.walk(data.proc_visitor, &proc_type.expr_base)
						//if ident, ok := last_ident_node.derived.(^ast.Ident); ok {
						//	log.info(ident)
						//}
						//log.info(proc_type)
						//log.info(" ")
					}
				}
				return visitor
			},
			data = &root_visitor_data,
		}

		log.info(strings.to_string(builder))

		if parse_ok {
			for decl in file.decls {
				if foreign_block_decl, ok := decl.derived_stmt.(^ast.Foreign_Block_Decl); ok {
					ast.walk(&visitor, &foreign_block_decl.node)
				}
			}
		} else {
			log.fatal("Error parsing file:", filepath)
		}

	} else {
		log.fatal("Error reading file:", filepath)
	}


}
