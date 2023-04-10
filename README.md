"# Node-Tree-Forest-classes-for-AD" 
This is  a set of classes that can be used for getting stats from AD groups, building nesting tree structuree etc.

Among the classes, 

    class-JohnAD" : this is merely a container to hold a bunch of AD essential functions. This class was build mainly for the reason in my work environment not all DCs are accessible. Some are behind firewall, so there is a need to properly find a DC that for all get-ad* cmdlets. A lot of functions are around this requirement

    Group         : this is better called "Node" as in the class series of group-[tree|loop]-forest, 
                    it should really be node-tree-forest. This class stores bare minimum info required
                    for constructing higher level structure (Tree/Loop), namely nodeName/children
                    with representation of "groupDN/members"

    Tree          : All nodes that form a tree. Branch building stops at when a node is found in
                    inventory, meaning this node was processed already in another branch. Strictly
                    speaking, this forms a loop under a branch, but for simplicity purpose, such loop
                    (that resides within a tree) are not process again in "loop" class

    Loop          : All nodes in a loop (circular nesting in AD group nesting sense). Please note that 
                    not all loops will be included in a "loop" class. Please see note above for "tree" 
                   
                   
Usage: see demo file                   
