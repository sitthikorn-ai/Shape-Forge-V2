with open('tools.rb', 'rb') as f:
    content = f.read()

# Fix: @pts[1] is chain[-2] (not the cap), so we need to use @ip1.position or chain endpoint
# Change from @pts[1].vector_to(@pts[0]) to computing offset from the actual cap position

old = b'\t\t\t\t\t\t\t\t# @pts[1] is the original cap click position, @pts[0] is cursor\r\n\t\t\t\t\t\t\t\toffset_vec = @pts[1].vector_to(@pts[0])'

new = b'\t\t\t\t\t\t\t\t# @pts[0] is cursor, compute offset from actual cap position (not @pts[1] which is chain[-2])\r\n\t\t\t\t\t\t\t\tcap_world = @member.chain.path[cap_idx].transform(member_trans)\r\n\t\t\t\t\t\t\t\toffset_vec = cap_world.vector_to(@pts[0])'

count = content.count(old)
if count == 1:
    content = content.replace(old, new, 1)
    with open('tools.rb', 'wb') as f:
        f.write(content)
    print("Fix applied successfully!")
else:
    print(f"ERROR: Found {count} occurrences")
