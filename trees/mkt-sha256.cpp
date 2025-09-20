// Implementation of a merkle tree (not sparse) on c++
// with arity 2 with some basic functions using sha256 hashing

#include <cassert>
#include <cmath>
#include <execution>
#include<openssl/sha.h>
#include <iostream>
#include <string> 
#include <vector>

using namespace std;

// Function to compute sha256 of a string
string sha256(string input){
    unsigned char hash[SHA256_DIGEST_LENGTH];

    SHA256(reinterpret_cast<const unsigned char*>(input.c_str()), input.size(), hash);

    char buf[2*SHA256_DIGEST_LENGTH+1];
    for (int i = 0; i < SHA256_DIGEST_LENGTH; i++)
        sprintf(buf + (i*2), "%02x", hash[i]);
    buf[2*SHA256_DIGEST_LENGTH] = 0;
    return string(buf);
}

// Linked list to construct tree
struct bNode{
    string hash;
    bNode* parent;
    bNode* sibling;
    bool is_left;
    bNode(const string& to_hash, bool left) : hash(to_hash), parent(nullptr), sibling(nullptr), is_left(left) {}
};

// Function that builds tree and stores lowest level 
bNode* buildMerkleTree(vector<string> data_block, vector<bNode*>& leaves){
    vector<bNode*> currentLevel;
    int c = 0;
    for (const auto block : data_block ){
        bNode* leaf = new bNode(sha256(block), false);
        if (c%2 == 0){
            leaf -> is_left = true;
        }
        c+=1;
        currentLevel.push_back(leaf);
        leaves.push_back(leaf);
    }

    if (currentLevel.size()%2 == 1){
        currentLevel.push_back(new bNode(sha256("0"), false));
    }

    while (currentLevel.size() > 1) {
        vector<bNode*> nextLevel;
        c = 0;
        for (int i =0; i<currentLevel.size(); i=i+2){
            bNode* left = currentLevel[i];
            assert(left -> is_left == true);
            bNode* right = currentLevel[i+1];
            assert(right -> is_left == false);
            string parentHash = sha256(left -> hash + right -> hash);
            bNode* parentNode = new bNode(parentHash, false);
            if(c%2 == 0){
                parentNode -> is_left = true;
            }
            left -> parent = parentNode;
            right -> parent = parentNode;
            left -> sibling = right;
            right -> sibling = left;
            nextLevel.push_back(parentNode);
            c+=1;
        }

        if (nextLevel.size()% 2 == 1 && nextLevel.size() > 1){
            nextLevel.push_back(new bNode(sha256("0"), false));
        }

        currentLevel = move(nextLevel);
    }

    return currentLevel.front();
}

// Function to update particular node's value
void updateMerkleTree(bNode* leaf, string new_val){
    leaf -> hash = sha256(new_val);
    bNode* current = leaf;
    while (current -> parent != nullptr) {
        bNode* next = current -> parent;
        bNode* sibling = current -> sibling;
        next -> hash = sha256(current -> hash + sibling -> hash);
        current = next;
    }
}

// Function to verify whether a value is correct by comparing it to known root. 
bool verifyElement(vector<bNode*> leaves, int index, string data, bNode* root){
    bNode* current = leaves[index];
    string currentHash = sha256(data);
    while (current -> parent != nullptr) {
        bNode* sibling = current -> sibling;
        string data_hash = sha256(data);
        if (current -> is_left){
            currentHash = sha256(currentHash + sibling -> hash);
        }
        else {
            currentHash = sha256(sibling -> hash + currentHash);
        }
        current = current -> parent;
    }

    if (root -> hash == currentHash){
        cout << "Data is verified!" << endl;
        return true;
    }
    else {
        cout << "Data has been compromised!" << endl;
        return false;
    }
}


int main (){
    vector<string> data_block = { "block1", "block2", "block3", "block4"};
    vector<bNode*> leaves;
    bNode* root = buildMerkleTree(data_block, leaves);

    cout << "Original Merkle Root: " << root-> hash << endl;

    bool verified = verifyElement(leaves, 2, "block3", root);
    cout << verified << endl;
    return 0;
}

