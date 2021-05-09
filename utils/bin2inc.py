""" Process a HP-71B .BIN file and output a .INC file """
import sys

# Main function
# An HP-71B BIN file is just a binary image of a ROM, with nibbles
# arranged as bytes, low first then high in the byte. An INC file is
# the ASCII Hex equivalent of each byte, 16 bytes per line with a
# comma in-between each for human readability. Lines are terminated
# with a carriage return.
def main():
    
    if len(sys.argv)==1:
        input_file = open(sys.stdin,'rb')
    elif len(sys.argv)==2:
        input_file = open(sys.argv[1],'rb')
    else:
        input_file = open(sys.argv[1],'rb')
        sys.stdout = open(sys.argv[2], 'w')
    
    #parseargs()
    count = 0
    bindata = list(input_file.read())
    sys.stdout.write("    radix hex\n")
    for byte in bindata:
        if (count % 16) == 0:
            sys.stdout.write("\n    db  ")
        sys.stdout.write("{0:03X}".format(byte))
        count = count + 1
        if (count % 16) != 0:
            sys.stdout.write(",")
    sys.stdout.write("\n")

main()