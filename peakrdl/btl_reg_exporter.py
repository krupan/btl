from systemrdl import rdltypes
from systemrdl.node import AddrmapNode, RegfileNode, RootNode

from peakrdl.plugins.exporter import ExporterSubcommandPlugin


def indent(level):
    indent_amount = 4
    return " " * indent_amount * level


def reg_inst_name(reg):
    name = reg.inst_name
    if hasattr(reg, "current_idx") and reg.current_idx:
        name += f"_{reg.current_idx[0]}"
    return name


class BtlRegDescriptor(ExporterSubcommandPlugin):
    short_desc = "btl reg exporter"
    long_desc = "Exports B Testbench Library register code"

    def add_exporter_arguments(self, arg_group: "argparse.ArgumentParser"):
        pass

    def do_export(self, top_node: "AddrmapNode", options: "argparse.Namespace"):
        btl_reg_exporter = BtlRegExporter()
        btl_reg_exporter.export(top_node, options.output)


class BtlRegExporter:
    def make_class_name(self, node):
        return node.inst_name.title().replace("_", "")

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
        reset = int(field.get_property("reset"))
        return f"'h{reset:x}"

    def get_info_str(self, node, level):
        array_ind = ""
        if hasattr(node, "current_idx") and node.current_idx:
            array_ind = f"{node.current_idx}"
        info_str = f"{indent(level)}level {level}: {type(node).__name__}: "
        info_str += f"{node.inst_name}{array_ind}"
        if hasattr(node, "address_offset"):
            info_str += f", offset: {node.address_offset}"
        if hasattr(node, "lsb"):
            info_str += f", bits: [{node.msb}:{node.lsb}]"
        return info_str

    def calculate_column_widths(self, fields):
        widths = {}
        widths["lsb"] = max(len(str(f.lsb)) for f in fields)
        widths["lsb"] = max(widths["lsb"], len("lsb"))

        widths["size"] = max(len(str(f.width)) for f in fields)
        widths["size"] = max(widths["size"], len("size"))

        widths["name"] = max(len(f'"{f.inst_name}"') for f in fields)
        widths["name"] = max(widths["name"], len("name"))

        widths["attr"] = max(len(self.attr_str(f)) for f in fields)
        widths["attr"] = max(widths["attr"], len("attr"))

        widths["reset"] = max(len(self.reset_str(f)) for f in fields)
        widths["reset"] = max(widths["reset"], len("reset"))
        return widths

    def get_field_dec_start(self, idx, num_fields):
        idx_str = str(idx).rjust(len(str(num_fields - 1)))
        return f"f[{idx_str}] = new("

    def field_header_comment(self, len_field_dec, widths):
        comment = "//"
        h_lsb = "lsb".rjust(widths["lsb"] + len_field_dec - len(comment))
        h_size = "size".rjust(widths["size"])
        h_name = "name".center(widths["name"])
        h_reset = "reset".rjust(widths["reset"])
        h_attr = "attr"
        # Notice the explicit spacing around the commas here
        output = f"{comment}{h_lsb}, {h_size}, {h_name} , {h_reset} ,"
        return output + f" {h_attr}"

    def declare_field(self, field, widths):
        # ljust = left align, rjust = right align
        lsb_str = str(field.lsb).rjust(widths["lsb"])
        size_str = str(field.width).rjust(widths["size"])
        name_str = f'"{field.inst_name}"'.ljust(widths["name"])
        reset_str = self.reset_str(field).rjust(widths["reset"])
        attr_str = self.attr_str(field).ljust(widths["attr"])
        line = f"{lsb_str}, {size_str}, {name_str} , "
        line += f"{reset_str} , {attr_str});"
        return line

    def declare_register(self, reg, level):
        out = []
        desc = reg.get_property("desc")
        if desc:
            out.append(f"{indent(level)}// {desc}")
        out.append(f"{indent(level)}btl_regs::Reg {reg_inst_name(reg)} = new(")
        level += 1
        out.append(f'{indent(level)}.name_in("{reg_inst_name(reg)}"),')
        out.append(f"{indent(level)}.offset_in({reg.address_offset}),")
        out.append(f"{indent(level)}.size_bytes_in({reg.size}));")
        return out

    def process_reg(self, reg, level):
        name = reg.get_property("name")
        reg_lines = [f"{indent(level)}begin // {name}, offset {reg.address_offset}"]
        level += 1
        reg_lines.extend(self.declare_register(reg, level))
        reg_lines.append(f"{indent(level)}btl_regs::Fields f;")
        fields = reg.fields()
        widths = self.calculate_column_widths(fields)
        for idx, field in enumerate(fields):
            field_dec_start = self.get_field_dec_start(idx, len(fields))
            if idx == 0:
                reg_lines.append(
                    f"{indent(level)}"
                    + self.field_header_comment(len(field_dec_start), widths)
                )
            reg_lines.append(
                f"{indent(level)}{field_dec_start}" + self.declare_field(field, widths)
            )
        reg_lines.append(f"{indent(level)}{reg_inst_name(reg)}.add_fields(f);")
        reg_lines.append(
            f"{indent(level)}regs[{reg.address_offset}] = {reg_inst_name(reg)};"
        )
        level -= 1
        reg_lines.append(f"{indent(level)}end")
        return reg_lines

    def initialize_nested_classes(self, level, nested_classes):
        output = []
        if nested_classes:
            output.append("")
            for nc in nested_classes:
                output.append(f"{indent(level)}foreach({nc.inst_name}[i]) begin")
                level +=1
                output.append(f"{indent(level)}{nc.inst_name}[i] = new('h{nc.raw_address_offset:x} * {nc.array_stride}, {nc.size});")
                level -= 1
                output.append(f"{indent(level)}end")
            output.append("")
        return output

    def instantiate_nested_classes(self, level, nested_classes):
        output = []
        if(nested_classes):
            output.append("")
            output.append(f"{indent(level)}// nested classes")
            for nc in nested_classes:
                output.append(
                    f"{indent(level)}{self.make_class_name(nc)} {nc.inst_name}{nc.array_dimensions};"
                )
            output.append("")
        return output

    def process_addrmap(self, addrmap, level):
        cls = [
            f"{indent(level)}class {self.make_class_name(addrmap)} extends "
            "btl_regs::AddrMap;"
        ]
        # too bad addrmap.addrmaps() and addrmap.regfiles() don't
        # exist
        level += 1
        nested_classes = []
        for child in addrmap.children():
            if isinstance(child, (AddrmapNode, RegfileNode)):
                nested_classes.append(child)
                cls.extend(self.process_addrmap(child, level))
        cls.extend(self.instantiate_nested_classes(level, nested_classes))
        cls.append(
            f"{indent(level)}function new(btl::Address base_addr, int unsigned "
            "size_bytes);"
        )
        level += 1
        cls.append(f"{indent(level)}super.new(base_addr, size_bytes);")
        cls.append(f'{indent(level)}name = "{addrmap.get_property("name")}";')
        cls.extend(self.initialize_nested_classes(level, nested_classes))

        for reg in addrmap.registers():
            cls.extend(self.process_reg(reg, level))
        level -= 1
        cls.append(f"{indent(level)}endfunction : new")

        level -= 1
        cls.append(f"{indent(level)}endclass : {self.make_class_name(addrmap)}")
        return cls

    def export(self, node, path):
        """
        Parameters
        ----------
        node: AddrmapNode
            Top-level SystemRDL node to export.
        path:
            Path to save the exported SystemVerilog file.
        """
        # If it is the root node, skip to top addrmap
        if isinstance(node, RootNode):
            node = node.top

        if not isinstance(node, AddrmapNode):
            raise TypeError(
                f"'node' argument expects type AddrmapNode or MemNode. Got '{type(node).__name__}'"
            )
        classes = [
            [
                "// generated with peakrdl btl-reg-exporter",
                f"// from {path}\n\n",
            ]
        ]
        classes.append(self.process_addrmap(node, 0))
        with open(path, "w", encoding="utf-8") as output:
            for cls in classes:
                output.write("\n".join(cls))
