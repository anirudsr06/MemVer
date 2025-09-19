#include <openssl/sha.h>
#include <iostream>
#include <string>
#include <unordered_map>
#include <vector>

using namespace std;

// SHA256 helper
string sha256(const string& input) {
    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256(reinterpret_cast<const unsigned char*>(input.c_str()), input.size(), hash);

    char buf[2*SHA256_DIGEST_LENGTH+1];
    for (int i = 0; i < SHA256_DIGEST_LENGTH; i++)
        sprintf(buf + (i*2), "%02x", hash[i]);
    buf[2*SHA256_DIGEST_LENGTH] = 0;
    return string(buf);
}


// Precompute default empty subtree hashes
vector<string> buildDefaultHashes(int depth) {
    vector<string> defaults(depth+1);
    defaults[0] = sha256("0"); 
    for (int i = 1; i <= depth; i++) {
        defaults[i] = sha256(defaults[i-1] + defaults[i-1]);
    }
    return defaults;
}

struct SparseMerkleTree {
    int depth;
    vector<string> defaultHashes;
    unordered_map<string, string> nodes; 
    string root;

    SparseMerkleTree(int d) : depth(d) {
        defaultHashes = buildDefaultHashes(depth);
        root = defaultHashes[depth]; 
    }

    // function to update/add new leaf
    void update(const string& keyBits, const string& value) {
        if ((int)keyBits.size() != depth) {
            cerr << "Key length must equal tree depth (" << depth << ")\n";
            return;
        }

        string current = sha256(value);
        nodes[keyBits] = current;

        for (int level = 0; level < depth; level++) {
            int pos = depth - level - 1;
            char bit = keyBits[pos];

            string parentKey = keyBits.substr(0, pos);

            string siblingKey = keyBits;
            siblingKey[pos] = (bit == '0') ? '1' : '0';
            siblingKey = siblingKey.substr(0, pos+1);

            string siblingHash;
            if (nodes.find(siblingKey) != nodes.end()) {
                siblingHash = nodes[siblingKey];
            } else {
                siblingHash = defaultHashes[level];
            }

            if (bit == '0')
                current = sha256(current + siblingHash);
            else
                current = sha256(siblingHash + current);

            nodes[parentKey] = current;
        }

        root = current;
    }

    string getRoot() const {
        return root;
    }
};

int main() {
    SparseMerkleTree smt(4); 

    cout << "Initial Root: " << smt.getRoot() << endl;

    smt.update("0100", "Bob");
    smt.update("0110", "Alice");
    smt.update("1110", "Charlie");
    smt.update("1111", "David");

    cout << "Root After Inserts: " << smt.getRoot() << endl;

    smt.update("0110", "Alice_2");
    cout << "Root After Alice update: " << smt.getRoot() << endl;
    for (auto& [key, hash] : smt.nodes){
        cout << "Key: " << key << " Node " << hash << endl;
    }
    return 0;
}

