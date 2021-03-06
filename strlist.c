#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "strlist.h"

struct StrNode* create_str_node(char *val, struct StrNode *next) {
    struct StrNode *node = (struct StrNode*)malloc(sizeof(struct StrNode));
    node->val = val;
    node->next = next;
    return node;
}

void init_str_list(struct StrList *lst) {
    lst->head = NULL;
    lst->size = 0;
}

void free_str_list(struct StrList *lst) {
    struct StrNode *curr = lst->head;
    struct StrNode *next = NULL;
    while (curr != NULL) {
        next = curr->next;
        free(curr);
        curr = next;
    }
}

void append_str(struct StrList *lst, char *val) {
    if (lst->size == 0) {
        lst->head = create_str_node(val, NULL);
    } else {
        struct StrNode *curr = lst->head;
        while (curr->next != NULL) {
            curr = curr->next;
        }
        curr->next = create_str_node(val, NULL);
    }
    lst->size++;
}

void remove_str(struct StrList *lst, int idx) { // TODO: handle index out of bounds
    if (idx == 0) {
        struct StrNode *tmp = lst->head;
        lst->head = tmp->next;
        free(tmp);
        lst->size--;
    } else {
        struct StrNode *tmp = lst->head;
        struct StrNode *prev;
        int i = 0;
        while (i < idx && i < lst->size - 1) {
            prev = tmp;
            tmp = tmp->next;
            i++;
        }
        prev->next = tmp->next;
        free(tmp);
        lst->size--;
    }
}

char *get_str(struct StrList *lst, int idx) { // TODO: handle index out of bounds
    if (idx == 0) {
        return lst->head->val;
    }
    struct StrNode *curr = lst->head;
    int i = 0;
    while(i < idx && i < lst->size - 1) {
        curr = curr->next;
        i++;
    }
    return curr->val;
}

void insert_str(struct StrList *lst, int idx, char *val) {
    if (idx == 0) {
        lst->head = create_str_node(val, lst->head);
    } else {
        struct StrNode *curr = lst->head;
        struct StrNode *prev;
        int i = 0;
        while (i < idx && i < lst->size) {
            prev = curr;
            curr = curr->next;
            i++;
        }
        prev->next = create_str_node(val, curr);
    }
    lst->size++;
}

int index_str(struct StrList *lst, char *val) {
    struct StrNode *curr = lst->head;
    int i = 0;
    while (curr != NULL) {
        if (strcmp(curr->val, val) == 0) {
            return i;
        }
        curr = curr->next;
        i++;
    }
    return -1;
}

char *pop_str(struct StrList *lst, int idx) {
    if (idx == 0) {
        struct StrNode *tmp = lst->head;
        lst->head = tmp->next;
        char *val = tmp->val;
        free(tmp);
        lst->size--;
        return val;
    } else {
        struct StrNode *tmp = lst->head;
        struct StrNode *prev;
        int i = 0;
        while (i < idx && i < lst->size - 1) {
            prev = tmp;
            tmp = tmp->next;
            i++;
        }
        prev->next = tmp->next;
        char *val = tmp->val;
        free(tmp);
        lst->size--;
        return val;
    }
}

void assign_str(struct StrList *lst, int idx, char *val) {
    if (idx == 0) {
        lst->head->val = val;
    } else {
        struct StrNode *node = lst->head;
        int i = 0;
        while (i < idx && i < lst->size - 1) {
            node = node-> next;
            i++;
        }
        node->val = val;
    }
}

int str_list_size(struct StrList *lst) {
    return lst->size;
}

char contains_str(struct StrList *lst, char *val) {
    if (index_str(lst, val) == -1) {
        return 0;
    }
    return 1;
}

void copy_str_list(struct StrList *src, struct StrList *tgt) {
    struct StrNode *node = src->head;
    while (node != NULL) {
        append_str(tgt, node->val);
        node = node->next;
    }
}

void print_str_list(struct StrList *lst) {
    struct StrNode *curr = lst->head;
    printf("%s ", "[");
    while (curr != NULL) {
        printf("%s ", curr->val);
        curr = curr->next;
    }
    printf("]\n");
}
