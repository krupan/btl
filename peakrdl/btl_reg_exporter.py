import os
import sys

from systemrdl import rdltypes
from systemrdl.node import (
    AddrmapNode,
    FieldNode,
    RegfileNode,
    RegNode,
    RootNode,
)

from peakrdl.plugins.exporter import ExporterSubcommandPlugin


def indent(level):
    indent_amount = 4
    return " " * indent_amount * level


def make_class_name(node):
    return node.inst_name.title().replace("_", "")


def attr_str(field):
    mapping = {
        rdltypes.AccessType.r: "btl_regs::RO",
        rdltypes.AccessType.rw: "btl_regs::RW",
        rdltypes.AccessType.w: "btl_regs::WO",
    }
    if field.get_property("onwrite") == rdltypes.OnWriteType.woclr:
        return "btl_regs::RW1C"
    return mapping[field.get_property("sw")]


def reset_str(field):
    reset = field.get_property("reset")
    if reset is None:
        print(
            f"ERROR: no reset property for {field.inst_name}", file=sys.stderr
        )
        sys.exit(-1)
    return f"'h{reset:x}"


def get_addrmap_constructor_params(addrmap, offset):
    return f"{addrmap.size}, 'h{addrmap.raw_address_offset:x}{offset});"


def get_reg_constructor_params(reg, offset):
    name = reg.get_property("name")
    # you need to use raw_address_offset in case its an array
    return f'"{name}", {reg.size}, \'h{reg.raw_address_offset:x}{offset});'


def get_field_constructor_params(field):
    name = field.get_property("name")
    attr = attr_str(field)
    reset = reset_str(field)
    return f'"{name}", {attr}, {reset}, {field.msb}, {field.lsb});'


def construct(member, level):
    array_ind = ""
    offset = ""
    output = []
    if not isinstance(member, FieldNode) and member.array_stride:
        array_ind = "[i]"
        offset = f"+ (i * {member.array_stride})"
    line = f"{indent(level)}{member.inst_name}{array_ind} = new("
    if isinstance(member, (AddrmapNode, RegfileNode)):
        output.append(line + get_addrmap_constructor_params(member, offset))
    if isinstance(member, RegNode):
        output.append(line + get_reg_constructor_params(member, offset))
    if isinstance(member, FieldNode):
        output.append(line + get_field_constructor_params(member))
    output.append(
        f"{indent(level)}children.push_back({member.inst_name}{array_ind});"
    )
    return output


def construct_members(members, level):
    output = []
    for m in members:
        if not isinstance(m, FieldNode) and m.array_stride:
            output.append(f"{indent(level)}foreach({m.inst_name}[i]) begin")
            level += 1
            output.extend(construct(m, level))
            level -= 1
            output.append(f"{indent(level)}end")
        else:
            output.extend(construct(m, level))
    return output


def declare_field_member(member, level):
    return f"{indent(level)}btl_regs::Field {member.inst_name};"


def declare_simple_member(member, level):
    line = f"{indent(level)}{make_class_name(member)} {member.inst_name}"
    if member.array_stride:
        line += f"{member.array_dimensions}"
    return line + ";"


def declare_class_members(members, level):
    output = []
    if members:
        output.append(f"{indent(level)}// class members")
    for m in members:
        if isinstance(m, FieldNode):
            output.append(declare_field_member(m, level))
        else:
            output.append(declare_simple_member(m, level))
    return output


def get_base_class(node):
    if isinstance(node, RegNode):
        return "btl_regs::Reg"
    return "btl_regs::AddrMap"


def declare_constructor(node, level):
    output = []
    if isinstance(node, RegNode):
        output.append(f"{indent(level)}function new(string name,")
        output.append(f"{indent(level)}             btl::Value size_bytes,")
        output.append(f"{indent(level)}             btl::Address offset);")
        level += 1
        output.append(f"{indent(level)}super.new(name, size_bytes, offset);")
    else:
        output.append(
            f"{indent(level)}function new(btl::Address base_addr, btl::Value size_bytes);"
        )
        level += 1
        output.append(f"{indent(level)}super.new(size_bytes, base_addr);")
        output.append(f'{indent(level)}name = "{node.get_property("name")}";')
    return output


def declare_btl_subclass(node, level):
    cls = [
        f"{indent(level)}class {make_class_name(node)} extends "
        f"{get_base_class(node)};"
    ]
    level += 1
    class_members = []
    for child in node.children():
        class_members.append(child)
        if isinstance(child, (AddrmapNode, RegfileNode, RegNode)):
            cls.extend(declare_btl_subclass(child, level))
    cls.extend(declare_class_members(class_members, level))
    cls.extend(declare_constructor(node, level))
    level += 1

    cls.extend(construct_members(class_members, level))
    level -= 1
    cls.append(f"{indent(level)}endfunction : new")

    level -= 1
    cls.append(f"{indent(level)}endclass : {make_class_name(node)}\n")
    return cls


def export(node, path):
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
            f"'node' argument expects type AddrmapNode or MemNode. Got "
            f"'{type(node).__name__}'"
        )
    source_file = path.replace(".svh", ".rdl")
    classes = [
        [
            "// generated with peakrdl btl-reg-exporter",
            f"// from {source_file}\n\n",
        ]
    ]
    classes.append(declare_btl_subclass(node, 0))
    if os.path.isdir(path):
        path += f"/{node.inst_name}.svh"
    with open(path, "w", encoding="utf-8") as output:
        for cls in classes:
            output.write("\n".join(cls))


class BtlRegDescriptor(ExporterSubcommandPlugin):
    short_desc = "btl reg exporter"
    long_desc = "Exports B Testbench Library register code"

    def add_exporter_arguments(self, arg_group: "argparse.ArgumentParser"):
        pass

    def do_export(
        self, top_node: "AddrmapNode", options: "argparse.Namespace"
    ):
        export(top_node, options.output)
