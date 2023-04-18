using module  ./class-JohnAD.psm1

<#
# This script provides 4 classes, 

    InventoryNode : store all nodes within a tree or loop. Customized info is also store here

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

# Both Group & Tree can be generalized to describe any tree structure. "Group" class is better renamed to 
# "Node", and "group.members" to "node.children" for general uses

# Class Tree also provides some aux attributes to proide tree level functions (or/and store tree level statistic)
# for node counting, tree printing, etc. Any other tree function can be added with similar approach

# Currently the tree constructor builds a tree top down starting from the given group. It does not buld upwards,
# meaning the resulting tree shows only half of a given group's relationship with others in AD - it shows only 
# descendants. Constructing both ancestor and descendants should be considered

# Design Limitations
    1. Not all loops are categorized under "loop" class. See above 
    2. Given a group, this script only builds tree downwards, i.e. it may produce only a branch if group given is not true tree top
    3. Loop constructor works very differently from that of Tree. Loop constructor does not take a group as input because 
       it doesn't know if given group is in a circular nesting chain. Loop's contructor takes a collection of nodes that are known
       already to be in loop(s) (by computing "all groups - groups in a tree"). See forest for more explanation why/how this is
       done this way
#> 

#region Usage
<#
    # givn a group name, print it's tree representation

    $gn=read-host "group name:"
    $go=get-adgroup $gn

    $dn = $go.distinguishedname
    $tree1 = [Tree]::new($dn)
    $tree1.saveTreeToTextFile(("./{0}_treeView.txt" -f $treeName))
    write-host $tree1.textTree
#>
#endregion Usage
class Group{
    <# 
    It's not class "Group"'s job to construct a tree
    This class only concerns the groups itself (single node), namely it should manage only groupName and set nestingLevel
    as instructed by other called. 
    Populating members field and tracking levels are jobs for class "Tree"

    ??? this class also should not store any actual AD-group-properties such as samAccountName/Enabled etc
    ??? because this class represents only a logical node for building trees
    ??? Actual AD related info should be stored in [tree]::inventory, which can be used to display or output or counting
    #>
    
    [string] $groupName #accepts only DN
    [int32] $nestingLevel=0 # if in a tree, the level count from treeTop; if in a loog, this is borrowed as "index" in Tarjan's algo
    [Group[]] $members =$null # array of children, includes only those who are also group
    
    Group([string]$groupName){
        $this.groupName=$groupName
        $this.nestingLevel =0
    }
    
    Group([string]$groupName,[int32]$nestingLevel){
        $this.groupName=$groupName
        $this.nestingLevel =$nestingLevel
    }
    
    [string]ToString(){
        return ("Group Name: {0}, level: {1}" -f $this.groupName,$this.nestingLevel)
    }
    
    [string] toShortForm(){ # could have used DN2shortForm, but customize for this script only to handle DNs with "*" prefix
        $gn=$this.groupName
        $result=""
        if ($gn -match "^\*") { 
            $result = "*" 
            $gn= $gn -replace "^\*"
        }
        $matchGroups=($gn | select-string -pattern '(^CN=)(.*?)(\,.*?DC=)(.*?)(,DC=.*$)' ).matches.groups  # regex grouping
        $result += ($matchGroups[4].value) + '\' + ($matchGroups[2].value)
        return $result
    }
} # class Group ends

class inventoryNode{ # Used for store detailed info about a group. Each Tree/Loop maintains its own inventory of nodes. 
    [string] $domain
    [string]    $DistinguishedName
    [string]    $SamAccountName
    [string]    $DirectParent
    [int32]    $nestingLevel

    inventoryNode([string]$domain,[string]$DistinguishedName,[string]$SamAccountName,[string]$DirectParent,[int32]$nestingLevel){
        $this.domain=$domain
        $this.DistinguishedName=$DistinguishedName
        $this.SamAccountName=$samAccountName
        $this.DirectParent=$DirectParent
        $this.nestingLevel=$nestingLevel
    }

    inventoryNode(){ # create a sample node with no meaningful properties
        $this.domain=""
        $this.DistinguishedName=""
        $this.SamAccountName=""
        $this.DirectParent=""
        $this.nestingLevel=0
    }


    [string]toCSVstring(){
        return $this|ConvertTo-Csv
    }
}
Class Tree{
<# A tree is nothing more than a group with some tree-level fields. Most of the tree construction work is done in polulatingMembers
    This class' constructors do NOT verify whether the AD group represented by treeTop atually has parent in reality
    It merely uses the group as a start point, as a logical head
    
    When circular/repeating detected, tree consturction will stop/skip duplicated node, avoid infinite loop and
    maintain a true tree graph
#>

    [group] $treeTop
    [hashtable] $inventory=@{} #all groups in a tree, {DN, inventoryNode} as key/value pair
    # this inventory is useful to detect circular nesting, and list a group in a tree only once. Also useful for enumerating groups

    #region comment about how level should be offerred
    # counting certain level shouldn't be a builtin property. Counting is offered with a method call that accepts any level
    # [int32] $count=0 # for counting number of nodes that are 3+ levels deep (level to start counting can be changed)
    #endregion
    [string[]] $textTree=@() # Indented text file representation of the tree. Only populated when saveTreeToTextFile function is called 
    
    hidden populateMembers([group]$groupNode,[string[]]$members){
        # When this function is called, the assumption is that $memmbers is not null.
        # $members is array of DN of members
        # Caller need to make sure $members is valid and not empty

        foreach ($member in $members){
            if($this.inventory.contains($member)){ #circular or repeating membership detected, skip
                # though we don't want to dead looping due to circular/duplicate nesting, we still want to record such entry
                # adding a prefix "*" to denote a duplicate/circular nesting

                $newGroupNode=[group]::new(("*"+$member),$groupNode.nestinglevel+1) # node for same group is listed again, padded with a * prefix
                #if($newGroupNode.nestingLevel -ge 3) {$this.count +=1}
                ($groupNode.members) += $newGroupNode
                continue
            } 

            if ($member -match "CN=ForeignSecurityPrincipals"){ #skip wellknown IDs
                # Group can have principals from above container as member. Such members are builtin 
                # well known IDs that can't be retrieved by get-ADuser or get-ADgroup, nor should we go further 
                # to check such objects

                # "CN=ForeignSecurityPrincipal" container is really not for "foreign IDs", rather some builtin IDs

                $newGroupNode=[group]::new(("*"+$member),$groupNode.nestinglevel+1)
                #if($newGroupNode.nestingLevel -ge 3) {$this.count +=1}
                ($groupNode.members) += $newGroupNode
                continue
            }
            
            #region get member object  from AD, process based on member type
            try{
                $domainName=[ADext]::DN2DomainNETBiosName($member)
                $server = [ADext]::DN2DC($member)
                $memberObj=get-adObject $member -server $server -properties objectClass ,member,samAccountName,enabled,distinguishedName
            }
            catch{
                write-host ("[ERROR @ populateMembers] Failed to get object {0}" -f $member) -backgroundcolor darkred
                write-host ("`t{0}]" -f $_.exception.message)  -backgroundcolor darkred
                continue
            }
            $memberType=$memberObj.objectClass
            if ($memberType -eq 'foreignSecurityPrincipal'){ # process foreign member: needs one extra step to retrieve real AD object from hosting domain
                try {($dc=[ADext]::SID2DC($memberObj.name))}
                catch{
                    write-host ("[ERROR @ populateMembers] SID2DC failed : group = {0} : memberSID = {1}" -f $groupNode.groupName,$memberObj.name)  -backgroundcolor darkred
                    write-host "This is expected for some well known IDs as their SID doesn't have domain SID"
                    continue
                }
                
                try { # get foreign object
                    $memberObj = get-adObject -ldapfilter ("(objectsid={0})" -f ($memberObj.name)) -server $dc -properties objectClass,member,samAccountName,enabled,distinguishedName
                }
                catch {
                    write-host ("[Warning @ populateMembers][Skipped] Failed to get foreign member from SID {0} in group {1} from DC {2}" -f ($memberObj.name),($groupNode.groupName),($dc)) -backgroundcolor darkred
                    continue
                }
                if($null -eq $memberObj){
                    continue
                }
                $memberType=$memberObj.objectClass
            } #foreign member ends
            
            
            #endregion get member object

            #region write current member into a new group node, then go further recursively
            if ($memberType -eq 'group') { # for type 'group', construct a node, then add node to members
                $newGroupNode=[group]::new($member,$groupNode.nestinglevel+1)
                $groupNode.members += $newGroupNode #add new node as child

                #region update inventory
                $inventoryItem=[inventoryNode]::new($domainName,$memberObj.distinguishedName,$memberObj.samAccountName,$groupNode.groupName,$groupNode.nestingLevel+1)
                
                # add new inventory
                $this.inventory[$memberObj.distinguishedName]=$inventoryItem
                #endregion update inventory
                
                # populate members recursively
                $this.populateMembers($newGroupNode,$memberobj.member)  
            }
            #endregion write current member into a new group node, then go further recursively
            
        } # enumerate members ends
    } # hidden function populateMembers ends

    hidden initTree([microsoft.activedirectory.management.adgroup]$group){
    <#
    # actual tree construction was done in a hidden fuction(populateMembers) so constructor can call it with more flexibility
    # This way we change code only in one place (here) instead of in multiple constructors
    #>
    
        #populating tree level fields, this includes treeTop node itself, and inventory info etc.
        $groupDN = $group.distinguishedName
        $domainName=[ADext]::DN2DomainNETBiosName($groupDN)
        $this.treeTop = [group]::new($groupDN)

        $inventoryItem=[inventoryNode]::new($domainName,$group.distinguishedName,$group.samAccountName,"",0)
        $this.inventory[$groupDN]=$inventoryItem
        
        if($group.member.count -gt 0){
            $this.populateMembers($this.treetop,$group.member) #populating members into $group.members
        }
    } # initTree ends
    
    hidden [string] populateTreeText([group]$group,[string]$leadingSpace,[boolean]$shortForm) {
        #print shortform group list otherwise print DN form
        
        if($shortForm){
            $s=$group.toShortForm()
        }
        else { $s = $group.groupName}
        
        $currentLine = $leadingSpace + $group.nestingLevel.toString() + " " + $s + "`r`n"
        $this.textTree += $currentLine
        foreach ($member in $group.members){
            $this.populateTreeText($member,("    "+$leadingSpace),$shortForm)
        }
        
        return $this.textTree
    } #populateTreeText ends
    
    hidden [boolean] populateTreeText([group]$group,[string]$leadingSpace,[boolean]$shortForm, [int32]$level) {
        <#
            given group node, generate a tree's text presentation

            $group - the group in scope
            $leadingSpace - leading space string to be used 
            $shortForm - whether to use group short name or DN
            $level -> only branches that are deeper than $level will be printed
        #>
        $printFlag=$false
        
        if ($group.nestingLevel -ge $level){
            $printFlag = $true
        }
        
        foreach ($member in $group.members){
            $childPrintFlag = ($this.populateTreeText($member,("    "+$leadingSpace),$shortForm,$level))
            if ($childPrintFlag) {$printFlag = $childPrintFlag}
        }

        if ($printFlag){
            if($shortForm){$s=$group.toShortForm()}
            else { $s = $group.groupName}
            $currentLine = $leadingSpace + $group.nestingLevel.toString() + " " + $s + "`r`n"
            $this.textTree = $currentLine + $this.textTree
        }
        return $printFlag
    } #populateTreeText ends
    
    Tree([microsoft.activedirectory.management.adgroup]$group) {#tree constructor 1
    <#
    # Tree constructor from AD group
    # this is just a call to initTree
    #>
    
    
        $this.initTree([microsoft.activedirectory.management.adgroup]$group)
    } #tree constructor 1 ends
    
    Tree([string]$groupDN) {# Tree constructor 2
    <#
    # Tree constructor from DN
    #>
        $server=[ADext]::DN2DC($groupDN)
        try{
            $ADgroup=get-adgroup -identity $groupDN -server $server -properties member,distinguishedName,samAccountName,enabled
        }
        catch {
            $ADgroup=$null
            write-host ("[ERROR @ Tree constructor] Failed to get AD group from {0}" -f $server)  -backgroundcolor darkred
        }
        $this.initTree($ADgroup)
    } # Tree constructor #2
    
    [void] saveTreeToTextFile([string]$filePath) {# generate text representation of tree. 
    
        $shortForm = $true
        $this.textTree=@()
        $this.populateTreeText($this.treetop,"",$shortForm)
        $this.textTree | out-file -filePath $filePath
    }

    [void] saveTrimmedTreeToFile([string]$filePath, [int32]$n) # generate tree branches that are n level and deeper
    {
        $shortForm = $true
        $this.textTree=@()
        $this.populateTreeText($this.treetop,"",$shortForm,$n)
        $this.textTree | out-file -filePath $filePath
    }

    [int32] countNodeDeeperThanLevel([int32]$level) # Count # of nodes that are certain $level deep(er)
    {
        [int32] $c = 0
        
        foreach($node in $this.inventory.GetEnumerator()){
            if ($node.value -ge $level) {$c +=1}
        }
        
        return $c
    }

    [System.Collections.ArrayList] listNodeDeeperThanLevel([int32]$level) # ArrayList of nodes that are certain $level deep(er)
    {
        $list = New-Object System.Collections.ArrayList
        foreach($node in $this.inventory.GetEnumerator()){
            if ($node.value -ge $level) {$list.add($node)}
        }
        
        return $list
    }

} # class Tree ends

Class Loop{ # used for representing circular nesting
    <# A loop is for circular nested groups. It will be organized as a single file chain
        all nodes have only one child regardless if the actual AD group has more than one
        children. Only child that forms the loop is included

        Essentially a loop is a special type of tree because we won't link tail of the loop
        back to head of loop. The link between head and tail is implicit
    #>
    
        hidden [string] $loopHead # a loop doesn't really have a head. This is only useful for generating $chainString in $this.setChainString as termination condtion in recursive calls
        [hashtable] $inventory=@{} #all groups in a loop, {name, inventoryNode} as key/value pair. 
        [string] $chainString # text representation of the loop as "a->b->c->a"
        #[string[]] $textLoop=@() # Indented text file representation of the tree. Only populated when saveTreeToTextFile function is called 

        hidden [string] setChainString([string]$key){ #generate a string that represents the loop "a->b->c->a"
            #$groupDN is any node in the loop
            $currentNode=$this.inventory[$key]
            $text = "{0}\{1}" -f $currentNode.domain, $currentNode.samAccountName
            if($currentNode.DirectParent -eq $this.loopHead){
                $loopHeadText = "{0}\{1}" -f $this.inventory[$this.loopHead].domain, $this.inventory[$this.loopHead].samAccountName
                return "{0} -> {1}" -f $loopHeadText,$text
            }
            return "{0} -> {1}" -f $this.setChainString($currentNode.DirectParent),$text
        }
        
        #region constructor loop
        loop([string[]]$loopMembers,[hashtable]$memberDetailedInfo){
        # $memberDetailedInfo was from $forest.loopCandidates
        # ------------------------------------
        # Data structure for $loopCandidates
        # ------------------------------------
        # [hashtable] $loopCandidates       = {key=DN, {$groupInfo}}
        # [psObject] $groupInfo             = {domain=domainName,ID=samAccountName,members=memberNode[]}
        # [psObject] $memberNode            = {DN,domain,ID}
        # ---------------------------------------------
 
            foreach ($loopmember in $loopMembers){
                $DirectParent=""
                foreach($key in $memberDetailedInfo.keys){
                    if($loopmember -in $memberDetailedInfo[$key].members.DN){
                        $DirectParent=$key
                        break
                    }
                }
                $inventoryItem=[inventoryNode]::new(
                    $memberDetailedInfo[$loopmember].domain,
                    $loopMember,
                    $memberDetailedInfo[$loopmember].ID,
                    $DirectParent, 
                    $loopmembers.count
                )
                $this.inventory[$loopmember]=$inventoryItem
            }

            # generate chain text once $this.inventory is built : 
            $this.loopHead = $loopMembers[0]
            $this.chainString=$this.setChainString($this.loopHead)

        }
        #endregion constructor loop

        [string[]] toCSVString() { # 
            return $this.inventory.Values|ConvertTo-Csv 
        }
}    


