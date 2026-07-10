from systemrdl import rdltypes
from systemrdl.node import AddrmapNode, MemNode, RootNode

from peakrdl.plugins.exporter import ExporterSubcommandPlugin


class BtlRegDescriptor(ExporterSubcommandPlugin):
    short_desc = "btl reg exporter"
    long_desc = "Exports B Testbench Library register code"

    def add_exporter_arguments(self, arg_group: "argparse.ArgumentParser"):
        pass

    def do_export(
        self, top_node: "AddrmapNode", options: "argparse.Namespace"
    ):
        btl_reg_exporter = BtlRegExporter()
        btl_reg_exporter.export(top_node, options.output)


class BtlRegExporter:
    # node: Union[AddrmapNode, RootNode]
    def export(self, node, path):
        """
        Parameters
        ----------
        node: AddrmapNode
            Top-level SystemRDL node to export.
        path:
            Path to save the exported XML file.
        """

        # If it is the root node, skip to top addrmap
        if isinstance(node, RootNode):
            node = node.top

        if not isinstance(node, (AddrmapNode, MemNode)):
            raise TypeError(
                f"'node' argument expects type AddrmapNode or MemNode. Got '{type(node).__name__}'"
            )

        output_lines = ["// generated with peakrdl btl-reg-exporter"]
        # declare all the registers
        indent = ""
        output_lines.append(f"{indent}package {node.inst_name};")
        indent += " " * 4
        output_lines.append(
            f"{indent}class {self.make_class_name(node)} "
            + "extends btl_regs::AddrMap;"
        )
        indent += " " * 4
        # declare and add fields to all the registers
        output_lines.append(
            f"{indent}function new(btl::Address base_addr, int unsigned size_bytes);"
        )
        indent += " " * 4
        output_lines.append(f"{indent}super.new(base_addr, size_bytes);")
        output_lines.append(f'{indent}name = "{node.get_property("name")}";')
        size_bytes = 0
        for reg in node.children():
            size_bytes += reg.size
        output_lines.append(f"{indent}size_bytes = {size_bytes};")
        for reg in node.children():
            output_lines.append(f"{indent}begin")
            indent += " " * 4
            output_lines.extend(self.declare_register(indent, reg))
            output_lines.append(f"{indent}btl_regs::Fields f;")
            widths = self.calculate_column_widths(reg)
            for i, field in enumerate(reg.fields()):
                # idx is special
                idx_str = str(i).rjust(len(str(len(reg.fields()) - 1)))
                if i == 0:
                    output_lines.append(
                        self.field_header_comment(
                            indent, self.get_field_dec(idx_str), widths
                        )
                    )
                output_lines.append(
                    self.declare_field(
                        indent, self.get_field_dec(idx_str), field, widths
                    )
                )
            output_lines.append(f"{indent}{reg.inst_name}.add_fields(f);")
            output_lines.append(
                f"{indent}regs[{reg.address_offset}] = {reg.inst_name};"
            )
            indent = indent[:-4]
            output_lines.append(f"{indent}end")
        indent = indent[:-4]
        output_lines.append(f"{indent}endfunction : new")
        indent = indent[:-4]
        output_lines.append(f"{indent}endclass : {self.make_class_name(node)}")
        indent = indent[:-4]
        output_lines.append(f"{indent}endpackage : {node.inst_name}");

        with open(path, "w", encoding="utf-8") as output:
            output.write("\n".join(output_lines))

    def make_class_name(self, node):
        return node.inst_name.title().replace("_", "")

    def get_field_dec(self, idx_str):
        return f"f[{idx_str}] = new("

    def declare_register(self, indent, reg):
        out = []
        name = reg.get_property("name")
        out.append(f"{indent}// {name}, offset {reg.address_offset}")
        desc = reg.get_property("desc")
        if desc:
            out.append(f"{indent}// {desc}")
        out.append(f"{indent}btl_regs::Reg {reg.inst_name} = new(")
        indent += " " * 4
        out.append(f'{indent}.name_in("{reg.inst_name}"),')
        out.append(f"{indent}.offset_in({reg.address_offset}),")
        out.append(f"{indent}.size_bytes_in({reg.size}));")
        return out

    def attr_str(self, field):
        mapping = {
            rdltypes.AccessType.r: "btl_regs::RO",
            rdltypes.AccessType.rw: "btl_regs::RW",
            rdltypes.AccessType.w: "btl_regs::WO",
        }
        if field.get_property("onwrite") == rdltypes.OnWriteType.woclr:
            return "btl_regs::RW1C"
        return mapping[field.get_property("sw")]

    def reset_str(self, field):
        if not field.get_property("reset"):
            return "0"
        return str(field.get_property("reset"))

    def calculate_column_widths(self, reg):
        widths = {}
        widths["lsb"] = max(len(str(f.lsb)) for f in reg.fields())
        widths["lsb"] = max(widths["lsb"], len("lsb"))

        widths["size"] = max(len(str(f.width)) for f in reg.fields())
        widths["size"] = max(widths["size"], len("size"))

        widths["name"] = max(len(f'"{f.inst_name}"') for f in reg.fields())
        widths["name"] = max(widths["name"], len("name"))

        widths["attr"] = max(len(self.attr_str(f)) for f in reg.fields())
        widths["attr"] = max(widths["attr"], len("attr"))

        widths["reset"] = max(len(self.reset_str(f)) for f in reg.fields())
        widths["reset"] = max(widths["reset"], len("reset"))
        return widths

    def field_header_comment(self, indent, field_dec, widths):
        comment = "//"
        h_lsb = "lsb".rjust(widths["lsb"] + len(field_dec) - len(comment))
        h_size = "size".rjust(widths["size"])
        h_name = "name".center(widths["name"])
        h_reset = "reset".rjust(widths["reset"])
        h_attr = "attr"
        # Notice the explicit spacing around the commas here
        output = f"{indent}{comment}{h_lsb}, {h_size}, {h_name} , {h_reset} ,"
        return output + f" {h_attr}"

    def declare_field(self, indent, field_dec, field, widths):
        # ljust = left align, rjust = right align
        lsb_str = str(field.lsb).rjust(widths["lsb"])
        size_str = str(field.width).rjust(widths["size"])
        name_str = f'"{field.inst_name}"'.ljust(widths["name"])
        reset_str = self.reset_str(field).rjust(widths["reset"])
        attr_str = self.attr_str(field).ljust(widths["attr"])
        line = f"{indent}{field_dec}{lsb_str}, {size_str}, {name_str} , "
        line += f"{reset_str} , {attr_str});"
        return line
